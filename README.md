# Whispr — Fast Voice-to-Text for macOS

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![License: MIT](https://img.shields.io/badge/License-MIT-green) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

A minimal, fast voice-to-text app for macOS. Press and hold to dictate, release to transcribe. Text is instantly pasted wherever your cursor is.

---

## Install

### Option 1 — Download DMG

[**Download latest release →**](https://github.com/product-noob/whispr-app/releases/latest)

Open the DMG and drag Whispr to Applications.

### Option 2 — One-line installer

```bash
curl -fsSL https://raw.githubusercontent.com/product-noob/whispr-app/main/install.sh | bash
```

### Option 3 — Build from source (Xcode)

**Requirements:** macOS 14+, Xcode 15+

```bash
git clone https://github.com/product-noob/whispr-app.git
cd whispr-app
open WhisprFlow.xcodeproj
# Hit ⌘R to build and run
```

---

## Features

- **Lightning Fast** — Press a hotkey, speak, release. Text appears instantly.
- **Minimal UI** — A tiny pill at the bottom of your screen. No clutter.
- **Privacy First** — Audio goes directly to OpenAI. No middleman servers.
- **Bring Your Own Key** — Use your own OpenAI API key. Pay only for what you use.
- **20 Free Transcriptions** — Try it before adding your API key.
- **Configurable Hotkeys** — `Fn`, `Control+Space`, `Option+Space`, or `Command+Shift+Space`.

---

## Usage

1. Press and hold your hotkey (default: `Fn` key)
2. Speak naturally
3. Release to transcribe
4. Text is automatically pasted where your cursor is

**First launch:** Right-click the app and select "Open" to bypass Gatekeeper.

**API key:** After 20 free transcriptions, add your own key at `platform.openai.com/api-keys` via Whispr Settings.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Microphone access
- Accessibility permission (for global hotkeys)
- OpenAI API key (after free trial)

---

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
cp -R ./build/Release/WhisprFlow.app ./dist/Whispr/
ln -s /Applications ./dist/Whispr/Applications
hdiutil create -volname "Whispr" \
  -srcfolder ./dist/Whispr \
  -ov -format UDZO \
  ./dist/Whispr.dmg

# Cleanup
rm -rf ./dist/Whispr ./build
```

---

## Privacy

- No accounts, no sign-up
- No telemetry or usage data collected
- Audio goes directly to OpenAI's API — no middleman servers
- API key stored locally on your Mac

---

## Contributing

PRs welcome. Open an issue first for larger changes.

---

## License

MIT — see [LICENSE](LICENSE) for details.

## Author

Created by [Prince Jain](https://princejain.me)
