# HTDemucs CoreML Model Preparation & INT8 Quantization

This document details the procedure for exporting Meta's **HTDemucs** (Hybrid Transformer Demucs) 4-source audio separation model (`htdemucs`) to an Apple CoreML package (`.mlpackage`) quantized with 8-bit integers (INT8) for high performance on Apple Neural Engine (ANE).

---

## 1. Prerequisites & Environment Setup

Run these commands in a Python 3.10+ environment (macOS or Linux):

```bash
# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install PyTorch, Demucs, and CoreMLTools
pip install --upgrade pip
pip install torch torchaudio
pip install demucs
pip install "coremltools>=7.0"
```

---

## 2. Model Architecture & Specifications

| Property | Value | Notes |
|---|---|---|
| **Architecture** | Hybrid Transformer Demucs (`htdemucs`) | 4-stem model from `facebookresearch/demucs` |
| **Stems** | 4 stems | Vocals, Drums, Bass, Other |
| **Input Shape** | `(1, 1, 441000)` or `(1, 2, 441000)` | 10 seconds of audio at 44.1 kHz |
| **Output Shape** | `(1, 4, 441000)` | 4 isolated audio stem channels |
| **Target Size** | ~35 MB - 48 MB | Quantized INT8 weights |
| **Compute Units** | `.all` | Runs on Apple Neural Engine + Metal GPU |

---

## 3. Automated Export Script

We have provided an automated export script in `scripts/export_coreml_model.py`.

Run the export script directly:

```bash
python scripts/export_coreml_model.py --output SuperHearing/Resources/Models/HTDemucs_quantized.mlpackage
```

---

## 4. Manual Export Walkthrough

If customizing the export pipeline manually:

```python
import torch
import coremltools as ct
from coremltools.optimize.coreml import (
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)
from demucs.pretrained import get_model

# 1. Load pretrained HTDemucs
demucs_model = get_model(name="htdemucs")
demucs_model.eval()

# 2. Wrapper module for fixed 10s chunk inference
class CoreMLDemucsWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, x):
        # x: (1, 1, 441000) -> duplicate to stereo (1, 2, 441000)
        stereo = x.repeat(1, 2, 1)
        # Demucs forward returns (batch, stems, channels, time)
        stems_stereo = self.model(stereo)
        # Downmix each stem to mono: (1, 4, 441000)
        stems_mono = stems_stereo.mean(dim=2)
        return stems_mono

wrapped_model = CoreMLDemucsWrapper(demucs_model)

# 3. Trace model with sample 10-second audio tensor
sample_input = torch.zeros(1, 1, 441000, dtype=torch.float32)
traced_model = torch.jit.trace(wrapped_model, sample_input)

# 4. Convert to CoreML
mlmodel = ct.convert(
    traced_model,
    inputs=[ct.TensorType(name="audio", shape=(1, 1, 441000))],
    outputs=[ct.TensorType(name="stems")],
    minimum_deployment_target=ct.target.iOS17,
    convert_to="mlprogram"
)

# 5. Apply INT8 Linear Quantization
config = OptimizationConfig(
    global_config=OpLinearQuantizerConfig(mode="linear_symmetric", weight_threshold=512)
)
quantized_model = linear_quantize_weights(mlmodel, config=config)

# 6. Save package
quantized_model.save("SuperHearing/Resources/Models/HTDemucs_quantized.mlpackage")
print("Successfully generated quantized HTDemucs model.")
```

---

## 5. Integrating with Xcode

1. Place `HTDemucs_quantized.mlpackage` into `SuperHearing/Resources/Models/`.
2. In Xcode, ensure the file is added to the **SuperHearing** target with **Target Membership** checked.
3. Xcode will automatically compile `.mlpackage` into `.mlmodelc` during the build phase.
4. When testing without the neural weight package, SuperHearing's built-in **DSP 4-Source Decomposition Filter** automatically activates as a graceful fallback so the entire UI, mixer, transport, and workflow can be tested immediately!
