# Whispr

A minimal, fast voice-to-text app for macOS. Press and hold to dictate, release to transcribe — works offline or with OpenAI.

## Features

- **Works Offline** — Three on-device models. No internet required, no data leaves your Mac.
- **Lightning Fast** — Press a hotkey, speak, release. Text appears where your cursor is.
- **Minimal UI** — A tiny floating pill at the bottom of your screen. No clutter.
- **Smart Post-Processing** — Auto-capitalization, filler word removal, voice commands ("new paragraph", "exclamation mark"), and a personal dictionary.
- **Privacy First** — No accounts, no telemetry, no servers. Local models run entirely on your Mac.

## Transcription Models

| Model | Type | Size | Notes |
|-------|------|------|-------|
| **Parakeet v3** | On-device (ANE) | ~250 MB | Recommended. Fast and accurate. |
| **Whisper Small** | On-device | ~190 MB | English-optimized, lightweight. |
| **Whisper Large Turbo** | On-device | ~600 MB | Highest accuracy, multilingual. |
| **OpenAI (gpt-4o-transcribe)** | Cloud | — | Requires API key. Best accuracy, needs internet. |

Local models are downloaded on first use and run entirely on your Mac. OpenAI is optional — use it if you want cloud-level accuracy or prefer not to download a model.

## Installation

1. [Download Whispr.dmg](https://github.com/product-noob/whispr-app/releases/download/v2.0.0/Whispr.dmg)
2. Open the DMG and drag Whispr to Applications
3. Launch Whispr — the onboarding will guide you through model selection and permissions

> On first launch, right-click the app and select **Open** to bypass Gatekeeper (the app is not code-signed).

## Usage

### Hotkey (Recommended)

1. Press and hold your hotkey (default: `Fn` key)
2. Speak naturally
3. Release to transcribe
4. Text is automatically pasted where your cursor is

### Click the Pill

1. Click the floating pill at the bottom of your screen
2. Click again when done speaking
3. Text is pasted automatically

### Configurable Hotkeys

- `Fn` key (default)
- `Control + Space`
- `Option + Space`
- `Command + Shift + Space`

## OpenAI Mode (Optional)

If you choose the OpenAI model, Whispr includes **20 free transcriptions** to try it out. After that, add your own API key:

1. Go to [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Create a new API key
3. Paste it in Whispr Settings

Local models have no usage limits.

## Building from Source

Requires Xcode 16+ and macOS 14.0+.

```bash
# Open in Xcode
open WhisprFlow.xcodeproj

# Or build from the command line
xcodebuild -project WhisprFlow.xcodeproj \
  -scheme WhisprFlow \
  -configuration Release \
  clean build
```

## Tech Stack

- **Language**: Swift
- **UI**: SwiftUI + AppKit
- **On-device ASR**: Parakeet v3 (FluidAudio / Apple Neural Engine), Whisper.cpp
- **Cloud ASR**: OpenAI Whisper API (gpt-4o-transcribe)
- **Audio**: AVAudioEngine

## Requirements

- macOS 14.0 (Sonoma) or later
- Microphone and Accessibility permissions

## Privacy

- No accounts or sign-up required
- No telemetry or usage data collected
- Local models run entirely on your Mac — audio never leaves your device
- OpenAI mode sends audio directly to OpenAI's API (no middleman)
- API key stored in your Mac's Keychain

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

Created by [Prince Jain](https://princejain.me)
