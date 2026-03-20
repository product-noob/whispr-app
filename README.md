# Whispr

A minimal, fast voice-to-text app for macOS. Press and hold to dictate, release to transcribe.

![Whispr Demo](website/screenshot.png)

## Features

- **Lightning Fast** - Press a hotkey, speak, release. Your words appear instantly.
- **Minimal UI** - A tiny pill at the bottom of your screen. No clutter.
- **Privacy First** - Audio goes directly to OpenAI. No middleman servers.
- **Bring Your Own Key** - Use your own OpenAI API key. Pay only for what you use.
- **20 Free Transcriptions** - Try it out before adding your own API key.

## Installation

1. Download Whispr.dmg from the website
2. Open the DMG and drag Whispr to Applications
3. Launch Whispr from Applications
4. Grant the required permissions:
   - **Microphone**: Required for voice recording
   - **Accessibility**: Required for global hotkeys

**Note**: On first launch, you may need to right-click the app and select "Open" to bypass Gatekeeper.

## Getting Started

### Try It Free

Whispr comes with **20 free transcriptions** so you can try it out. Just download and start using it immediately!

### Add Your Own API Key

After the free trial, you'll need to add your own OpenAI API key:

1. Go to [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Create a new API key
3. Open Whispr Settings and paste your key

That's it! The app is free forever with your own key.

## Usage

### Method 1: Hotkey (Recommended)

1. Press and hold your hotkey (default: `Fn` key)
2. Speak naturally
3. Release to transcribe
4. Text is automatically pasted where your cursor is

### Method 2: Click the Pill

1. Click the floating pill at the bottom of your screen
2. Click "Stop" when done speaking
3. Text is pasted automatically

### Configurable Hotkeys

- `Fn` key (default)
- `Control + Space`
- `Option + Space`
- `Command + Shift + Space`

## Requirements

- macOS 14.0 (Sonoma) or later
- OpenAI API key (for use after free trial)
- Microphone access
- Accessibility permission

## Privacy

Whispr is designed with privacy in mind:

- **No accounts** - No sign-up required
- **No telemetry** - No usage data collected
- **No servers** - Audio goes directly to OpenAI's API
- **Local storage** - Your API key is stored locally on your Mac

## Building from Source

```bash
# Open in Xcode
open WhisprFlow.xcodeproj

# Build and run
# Select WhisprFlow scheme and press Cmd+R
```

## Creating a Distribution DMG

```bash
# Build release version
xcodebuild -project WhisprFlow.xcodeproj \
  -scheme WhisprFlow \
  -configuration Release \
  clean build \
  CONFIGURATION_BUILD_DIR="./build/Release"

# Create DMG
mkdir -p ./dist/Whispr
cp -R ./build/Release/Whispr.app ./dist/Whispr/
ln -s /Applications ./dist/Whispr/Applications
hdiutil create -volname "Whispr" \
  -srcfolder ./dist/Whispr \
  -ov -format UDZO \
  ./dist/Whispr.dmg

# Cleanup
rm -rf ./dist/Whispr ./build
```

## Tech Stack

- **Language**: Swift
- **UI**: SwiftUI
- **Audio**: AVAudioEngine
- **Transcription**: OpenAI Whisper API (gpt-4o-transcribe)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

Created by [Prince Jain](https://princejain.me)

