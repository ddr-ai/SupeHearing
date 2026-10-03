# SuperHearing (iOS)

> Real-time Bluetooth audio capture, spectral noise reduction, distant sound enhancement, and 4-stem source separation powered by HTDemucs via CoreML.

---

## Overview

**SuperHearing** is an iOS application built for personal use with Ad Hoc self-signed distribution. It connects to any Bluetooth headset (e.g., AirPods Pro, Sony WF-1000XM5, Bose QuietComfort, or generic Bluetooth headsets), records wideband ambient audio, applies stationary noise reduction and distant speech intelligibility boosting via Apple's **Accelerate / vDSP** framework, and separates recordings into 4 distinct musical and vocal stems (**Vocals**, **Drums**, **Bass**, **Other**) using an INT8-quantized **HTDemucs** CoreML model.

---

## Technical Specifications

| Component | Technology | Description |
|---|---|---|
| **Platform** | iOS 17.0+ | Swift 5.9+, SwiftUI, Swift Concurrency (`async/await`) |
| **Audio Routing** | `AVAudioSession` | PlayAndRecord mode with Bluetooth HFP / A2DP priority & auto-reconnect |
| **DSP Engine** | Apple Accelerate `vDSP` | Real FFT (1024-frame, 50% hop, Hann window), Spectral Gating, Wiener filtering |
| **Distant Speech Boost** | Custom AGC & Limiter | Target RMS -18dBFS, 3.2kHz speech presence boost, 6.5kHz air boost, soft-knee limiter (-1dBFS) |
| **Stem Separation** | HTDemucs v4 via CoreML | INT8 quantized weight model (~40MB), 10s chunk inference with 1s crossfade |
| **Mixer** | `AVAudioEngine` | 4-channel synchronized stem mixer with faders, pan, solo, mute, and master export |
| **CI/CD** | GitHub Actions | Automated macOS runner building and signing Ad Hoc `.ipa` artifacts |

---

## Architecture & Project Structure

```
SuperHearing/
├── SuperHearing.xcodeproj/              # Xcode project with configured targets & build phases
│   ├── project.pbxproj
│   └── project.xcworkspace/
├── SuperHearing/
│   ├── App/
│   │   ├── SuperHearingApp.swift        # App entry point
│   │   └── AppDelegate.swift            # AudioSession lifecycle & background audio setup
│   ├── Views/
│   │   ├── MainTabView.swift            # Root tab bar (Record, Recordings, Settings)
│   │   ├── RecordingView.swift          # Live recording, scrolling waveform, dBFS VU meter
│   │   ├── FileListView.swift           # Recordings library, search, swipe actions, player
│   │   ├── ProcessingView.swift         # Spectral noise reduction & A/B audio comparison
│   │   ├── SeparationView.swift         # 4-source separation progress and stem cards
│   │   ├── StemMixerView.swift          # 4-track mixer with faders, solo, mute, pan, and master bus
│   │   └── SettingsView.swift           # DSP tuning, storage cache management, about
│   ├── ViewModels/
│   │   ├── RecordingViewModel.swift     # State machine (idle -> recording -> paused -> processing)
│   │   ├── FileListViewModel.swift      # File metadata management & persistence
│   │   ├── ProcessingViewModel.swift    # Background NR & enhancement pipeline
│   │   ├── SeparationViewModel.swift    # Chunked inference & stem management
│   │   ├── StemMixerViewModel.swift     # Multi-stem synchronized transport and gain
│   │   └── SettingsViewModel.swift      # UserDefaults persistence & cache calculations
│   ├── Models/
│   │   ├── AudioFile.swift              # Audio file model with duration, size, format, status
│   │   ├── Stem.swift                   # 4 stem enum (vocals, drums, bass, other) with styling
│   │   └── SeparatedAudio.swift         # Multi-stem bundle metadata
│   ├── Services/
│   │   ├── RecordingService.swift       # AVAudioEngine input node tap & Bluetooth routing
│   │   ├── NoiseReductionService.swift  # vDSP STFT, noise profiling, spectral gating, Wiener filter
│   │   ├── EnhancementService.swift     # AGC, multiband Biquad filters, 3:1 compression, limiter
│   │   ├── SeparationService.swift      # CoreML model loader + chunked inference + DSP fallback
│   │   └── PlaybackService.swift        # SingleAudioPlayer & synchronized StemMixerEngine
│   ├── Utilities/
│   │   ├── AudioBuffer.swift            # Circular audio buffer, RMS, dBFS, waveform downsampling
│   │   ├── STFT.swift                   # Forward & Inverse STFT using Accelerate vDSP
│   │   ├── AGC.swift                    # Biquad filter calculations, AGC envelope, peak limiter
│   │   └── Extensions.swift             # Time, Float, View, and URL helpers
│   └── Resources/
│       ├── Info.plist                   # Audio background mode, microphone & Bluetooth permissions
│       ├── SuperHearing.entitlements    # Device microphone and Bluetooth entitlements
│       ├── ExportOptions.plist          # Ad Hoc export configuration
│       ├── Assets.xcassets/             # AppIcon and AccentColor
│       └── Models/                      # Target directory for HTDemucs_quantized.mlpackage
├── SuperHearingTests/                   # Unit test suite (STFT, AGC, CircularBuffer, Stems, Codable)
├── SuperHearingUITests/                 # UI navigation and workflow test suite
├── .github/workflows/
│   └── build-ipa.yml                    # Automated GitHub Actions workflow building installable IPA
├── docs/
│   └── model_preparation.md            # HTDemucs export & INT8 quantization guide
├── scripts/
│   ├── export_coreml_model.py           # Python script to convert Demucs to CoreML INT8
│   └── generate_pbxproj.py              # Generator for Xcode project.pbxproj
├── Package.swift                        # SwiftPM configuration
├── .gitignore
└── README.md
```

---

## Getting Started

### Terminal Environment
For running CLI tools, Python scripts, and git workflows on Linux:
- Use **Ptyxis** as the terminal emulator (instead of Konsole).
- Ptyxis is configured as the default terminal (`ptyxis` command wrapper is available in `~/.local/bin/ptyxis`).
- Any legacy invocations directed to `konsole` are automatically bridged to `ptyxis`.

### 1. Opening the Project
Open `SuperHearing.xcodeproj` in Xcode 15.4 or newer on macOS:

```bash
open SuperHearing.xcodeproj
```

### 2. Preparing the HTDemucs CoreML Model
To run full neural source separation on device:

1. Install Python dependencies:
   ```bash
   pip install torch torchaudio demucs "coremltools>=7.0"
   ```
2. Run the export script:
   ```bash
   python scripts/export_coreml_model.py --output SuperHearing/Resources/Models/HTDemucs_quantized.mlpackage
   ```
3. Drag `HTDemucs_quantized.mlpackage` into the Xcode Project Navigator under `SuperHearing/Resources/Models/`, ensuring the target **SuperHearing** is checked.

> **Note**: Even if the CoreML model file has not been exported yet, the app includes an intelligent **DSP 4-source filter fallback** (vocal bandpass, drum transients, sub-bass filter, and ambient residue) that automatically activates so that all UI, playback, 4-track mixer, and export workflows can be tested immediately!

---

## GitHub Actions CI/CD (Ad Hoc IPA Generation)

The repository includes `.github/workflows/build-ipa.yml`, which triggers on pushes to `main` and version tags (`v*`).

### Required GitHub Repository Secrets
Under **Settings** → **Secrets and variables** → **Actions**, add:

| Secret Name | Description |
|---|---|
| `APPLE_CERTIFICATE` | Base64-encoded `.p12` distribution certificate (`base64 -i cert.p12`) |
| `APPLE_CERT_PASSWORD` | Password used to encrypt the `.p12` file |
| `MOBILEPROVISION` | Base64-encoded Ad Hoc provisioning profile (`base64 -i SuperHearing.mobileprovision`) |
| `TEAM_ID` | 10-character Apple Developer Team ID |

On tagging a release (e.g. `git tag v1.0.0 && git push origin v1.0.0`), the workflow builds the signed archive, exports `SuperHearing.ipa`, attaches it as a build artifact, and creates a GitHub Release with the installable IPA asset.

---

## Validation & Verification

- [x] **Audio Recording**: Captures 48kHz PCM audio with route changes handled automatically.
- [x] **Bluetooth Earbuds Priority**: Detects and binds to Bluetooth HFP / A2DP headsets.
- [x] **Spectral Noise Reduction**: vDSP STFT forward/inverse transforms with noise profiling, spectral gating, and Wiener filtering.
- [x] **Distant Speech Boost**: AGC envelope follower with speech formant EQ and soft-knee peak limiting.
- [x] **4-Stem Separation**: Chunked 10-second inference with crossfading for seamless stem generation.
- [x] **4-Track Stem Mixer**: Interactive faders, pan, solo, mute, master bus, and offline mix export.
- [x] **CI/CD Pipeline**: GitHub Actions workflow for signed Ad Hoc IPA generation.
- [x] **Unit & UI Tests**: Automated test suites covering DSP, buffer operations, models, and UI tabs.
