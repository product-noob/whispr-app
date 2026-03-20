# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

WhisprFlow (marketed as "Whispr") is a native macOS voice-to-text dictation app. Users press-and-hold a hotkey or click a floating pill UI, speak, release, and transcribed text is pasted into the active app. Uses OpenAI's Whisper API (`gpt-4o-transcribe`). English only, no on-device ASR, no streaming.

## Build & Run

```bash
# Build release (do NOT use CONFIGURATION_BUILD_DIR — it breaks SPM module resolution)
xcodebuild -project WhisprFlow.xcodeproj -scheme WhisprFlow -configuration Release clean build

# Build + create DMG (one command)
xcodebuild -project WhisprFlow.xcodeproj -scheme WhisprFlow -configuration Release clean build && \
APP=$(xcodebuild -project WhisprFlow.xcodeproj -scheme WhisprFlow -configuration Release -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | awk '{print $3}') && \
mkdir -p ./dist/WhisprFlow && \
cp -R "$APP/Whispr.app" ./dist/WhisprFlow/ && \
ln -s /Applications ./dist/WhisprFlow/Applications && \
hdiutil create -volname "WhisprFlow" -srcfolder ./dist/WhisprFlow -ov -format UDZO ./dist/WhisprFlow.dmg && \
rm -rf ./dist/WhisprFlow
```

Uses SPM packages (swift-transformers, SwiftWhisper, Sparkle, etc.). Xcode 16+, macOS 14.0+ target.

No tests exist in this project.

## Architecture

**AppDelegate is the orchestrator.** All services are instantiated and coordinated there — no DI framework, no Combine pipelines for coordination. Direct method calls between services.

### Core Flow
```
HotkeyManager (CGEventTap) or PillView (click)
  → AppDelegate.startRecording()
  → AudioRecorder (AVAudioEngine, 16kHz mono PCM → WAV, optional M4A compression if >500KB)
  → AppDelegate.stopRecording()
  → TranscriptionManager (multipart upload to OpenAI, dynamic timeout based on file size)
  → OutputDispatcher (Cmd+V simulation via CGEvent, fallback to clipboard)
  → HistoryStore (persists to UserDefaults as JSON)
```

### State Machine
`AppStateManager` holds a single `AppState` enum: `idle → recording → transcribing → idle` (or `→ error → idle`). All UI reacts to this. Invalid transitions are silently ignored.

### Key Services
- **AudioRecorder**: AVAudioEngine tap → WAV file in `~/Library/Application Support/WhisprFlow/recordings/`. Compresses to M4A via AVAssetExportSession if >500KB.
- **HotkeyManager**: CGEventTap (not NSEvent) for system-wide hotkey detection. Requires Accessibility permission. Supports fn, ctrl+space, opt+space, cmd+shift+space.
- **TranscriptionManager**: Multipart POST to OpenAI `/v1/audio/transcriptions`. Dynamic timeout: 45s base + 15s/MB, max 3 min. Single-request guard.
- **OutputDispatcher**: Simulates Cmd+V via CGEvent. 0.5s debounce. Falls back to clipboard-only if paste fails.
- **TrialTracker**: 20 free transcriptions OR 1 day. Uses XOR-obfuscated trial API key. After trial, prompts user for their own OpenAI key.

### UI Layer
- **PillWindow**: NSPanel subclass, `.floating` level, non-activating, bottom-center of screen. Hosts PillView.
- **PillView**: State-driven SwiftUI — collapsed idle → expanded hover → recording animation → transcribing spinner → error with retry.
- **MenuBarView**: Status bar popover with stats, trial progress, quick actions.
- **HistoryView**: Dashboard with Home/History/Settings tabs. Standalone NSWindow.
- **SettingsView**: API key, hotkey selection, output mode, permissions status.
- **AddAPIKeyView**: Modal shown when trial expires. Validates key starts with `sk-`.

### Storage
- **API key**: Base64-encoded in UserDefaults via `KeychainHelper` (not actual Keychain despite the name).
- **History**: JSON array in UserDefaults (`whisprflow_history`), auto-cleaned after 7 days.
- **Trial state**: UserDefaults (`whisprflow_first_launch`, `whisprflow_trial_count`).
- **Hotkey preference**: UserDefaults (`hotkeyType`).

### Permissions Required
1. **Microphone** — for audio capture (requested via AVCaptureDevice)
2. **Accessibility** — for global hotkeys + paste simulation (requested via AXIsProcessTrustedWithOptions, polled every 2s)

## Key Files

| File | Role |
|------|------|
| `AppDelegate.swift` | Service orchestration, window management, recording flow |
| `Models/AppStateManager.swift` | State machine (single source of truth) |
| `Services/AudioRecorder.swift` | AVAudioEngine recording + M4A compression |
| `Services/HotkeyManager.swift` | CGEventTap global hotkey detection |
| `Services/TranscriptionManager.swift` | OpenAI Whisper API client |
| `Services/OutputDispatcher.swift` | Paste simulation via CGEvent |
| `Services/TrialTracker.swift` | Free trial enforcement |
| `Utilities/ObfuscatedKey.swift` | XOR-obfuscated trial API key |
| `Utilities/Constants.swift` | Design tokens (colors, dimensions) |
| `Views/PillView.swift` | Main floating pill UI |
| `Views/PillWindow.swift` | NSPanel wrapper for pill |

## Design Decisions to Preserve

- **No streaming transcription** — full record → upload → paste. Intentional.
- **No on-device ASR** — relies entirely on OpenAI API.
- **AppDelegate as coordinator** — not a bug, it's the architecture. Don't introduce MVVM/VIPER.
- **CGEventTap over NSEvent** — required for non-focus-stealing global hotkeys.
- **UserDefaults for persistence** — no CoreData, no SQLite. The data is small.
- **Single language (English)** — hardcoded `language: "en"` in API call.
- **Not code-signed** — distributed as unsigned DMG. Users right-click → Open on first launch.

## Debug Logging

`logToFile()` in AppDelegate writes timestamped logs to `/tmp/whisprflow_debug.log`.
