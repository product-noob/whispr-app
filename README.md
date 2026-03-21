# Whispr

A minimal, fast voice-to-text app for macOS. Press and hold to dictate, release to transcribe.

## Features

- **Lightning Fast** — Press a hotkey, speak, release. Your words appear instantly.
- **Minimal UI** — A tiny floating pill at the bottom of your screen. No clutter.
- **Privacy First** — Audio goes directly to OpenAI. No middleman servers. No telemetry.
- **Bring Your Own Key** — Use your own OpenAI API key. Pay only for what you use.
- **20 Free Transcriptions** — Try it out before adding your own API key.

## Installation

1. [Download Whispr.dmg](https://github.com/product-noob/whispr-app/releases/download/v2.0.0/Whispr.dmg)
2. Open the DMG and drag Whispr to Applications
3. Launch Whispr from Applications
4. Grant the required permissions:
   - **Microphone** — for voice recording
   - **Accessibility** — for global hotkeys and paste

> On first launch, right-click the app and select **Open** to bypass Gatekeeper (the app is not code-signed).

## Getting Started

### Try It Free

Whispr comes with **20 free transcriptions**. Just download and start using it.

### Add Your Own API Key

After the free trial, add your own OpenAI API key:

1. Go to [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Create a new API key
3. Open Whispr Settings and paste your key

The app is free forever with your own key.

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
- **Audio**: AVAudioEngine
- **Transcription**: OpenAI Whisper API (gpt-4o-transcribe)

## Requirements

- macOS 14.0 (Sonoma) or later
- OpenAI API key (after free trial)

## Privacy

- No accounts or sign-up required
- No telemetry or usage data collected
- Audio goes directly to OpenAI's API
- API key stored locally on your Mac

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

Created by [Prince Jain](https://princejain.me)
