#!/usr/bin/env python3
"""
HTDemucs CoreML Export and INT8 Quantization Script for SuperHearing iOS.
Exports facebookresearch/demucs htdemucs model to CoreML INT8 mlpackage.
"""

import os
import sys
import argparse

def main():
    parser = argparse.ArgumentParser(description="Export HTDemucs to CoreML INT8 mlpackage")
    parser.add_argument(
        "--output",
        type=str,
        default="SuperHearing/Resources/Models/HTDemucs_quantized.mlpackage",
        help="Target output path for the .mlpackage"
    )
    parser.add_argument(
        "--chunk-seconds",
        type=int,
        default=10,
        help="Inference chunk duration in seconds (default: 10s)"
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=44100,
        help="Audio sample rate (default: 44100 Hz)"
    )
    args = parser.parse_args()

    try:
        import torch
        import coremltools as ct
        from coremltools.optimize.coreml import (
            OpLinearQuantizerConfig,
            OptimizationConfig,
            linear_quantize_weights,
        )
        from demucs.pretrained import get_model
    except ImportError as e:
        print(f"Error: Missing required Python packages ({e}).")
        print("Please install them with:")
        print("  pip install torch torchaudio demucs 'coremltools>=7.0'")
        sys.exit(1)

    print("==> Loading pretrained HTDemucs model...")
    model = get_model(name="htdemucs")
    model.eval()

    sample_count = args.chunk_seconds * args.sample_rate

    class HTDemucsMobileWrapper(torch.nn.Module):
        def __init__(self, core_model):
            super().__init__()
            self.core_model = core_model

        def forward(self, x):
            # Input: (1, 1, sample_count)
            # Duplicate mono to stereo for Demucs
            stereo = x.repeat(1, 2, 1)
            # Output: (batch, stems, channels, time)
            stems_stereo = self.core_model(stereo)
            # Downmix to mono: (1, 4, sample_count)
            stems_mono = stems_stereo.mean(dim=2)
            return stems_mono

    wrapper = HTDemucsMobileWrapper(model)

    print(f"==> Tracing model with {args.chunk_seconds}s dummy audio ({sample_count} samples)...")
    dummy_input = torch.zeros(1, 1, sample_count, dtype=torch.float32)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, dummy_input)

    print("==> Converting PyTorch model to CoreML mlprogram...")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="audio", shape=(1, 1, sample_count))],
        outputs=[ct.TensorType(name="stems")],
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram"
    )

    print("==> Quantizing weights to INT8...")
    opt_config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(mode="linear_symmetric", weight_threshold=512)
    )
    quantized_model = linear_quantize_weights(mlmodel, config=opt_config)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    print(f"==> Saving CoreML package to {args.output}...")
    quantized_model.save(args.output)
    print("==> Export and INT8 quantization completed successfully!")

if __name__ == "__main__":
    main()
