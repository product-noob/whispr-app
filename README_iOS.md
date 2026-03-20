# Whispr for iOS — Keyboard Extension

## Concept

Port WhisprFlow to iOS as a **custom keyboard extension**. Users switch to the Whispr keyboard, tap a mic button, speak, and transcribed text is inserted directly at the cursor — no clipboard, no app switching.

This is iOS's only viable path for "speak and text appears where you're typing."

---

## User Flow

### Setup (one-time)
1. Download Whispr from App Store
2. Open main app → enter OpenAI API key
3. Go to Settings → General → Keyboard → Add New Keyboard → Whispr
4. Enable "Allow Full Access" (required for mic + network)

### Daily use
1. User is typing in any app (iMessage, Notes, Slack, etc.)
2. Tap globe icon to switch to Whispr keyboard
3. Tap/hold the mic button to record
4. Release/tap again to stop
5. Spinner while transcribing via OpenAI API
6. Text inserted at cursor via `textDocumentProxy.insertText()`
7. Switch back to regular keyboard or keep dictating

---

## Architecture

### Two Targets

```
Whispr/
├── WhisprApp/                         # Main app (container)
│   ├── ContentView.swift              # API key setup, onboarding, history
│   ├── SharedConfig.swift             # App Group read/write
│   └── Info.plist
├── WhisprKeyboard/                    # Keyboard extension target
│   ├── KeyboardViewController.swift   # UIInputViewController subclass
│   ├── KeyboardAudioRecorder.swift    # Stripped-down AVAudioEngine recorder
│   ├── TranscriptionClient.swift      # OpenAI API call
│   ├── KeyboardUI.swift               # SwiftUI view hosted in UIKit
│   └── Info.plist
└── Shared/                            # Shared via App Group
    ├── AppGroupConstants.swift
    └── TranscriptionHistory.swift
```

### Data Sharing — App Groups

Main app and keyboard extension are separate processes. Shared data lives in an App Group container:

```swift
let defaults = UserDefaults(suiteName: "group.com.whispr.shared")

// Main app writes
defaults?.set(encodedKey, forKey: "api_key")

// Keyboard extension reads
let key = defaults?.string(forKey: "api_key")
```

API key, preferences, and history all go here.

### KeyboardViewController

The core of the extension. Subclasses `UIInputViewController`.

```swift
class KeyboardViewController: UIInputViewController {
    // self.textDocumentProxy.insertText("Hello") — injects text at cursor

    func startRecording() {
        state = .recording
        recorder = KeyboardAudioRecorder()
        recorder?.start()
    }

    func stopRecording() {
        state = .transcribing
        recorder?.stop { [weak self] audioURL in
            TranscriptionClient.transcribe(fileURL: audioURL) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text):
                        self?.textDocumentProxy.insertText(text)
                        self?.state = .idle
                    case .failure:
                        self?.state = .error
                    }
                }
            }
        }
    }
}
```

### Keyboard UI

Minimal — not a full keyboard, just a dictation tool:

```
┌─────────────────────────────────────┐
│  🌐          Whispr          ⌨️     │  globe to switch, keyboard icon for default KB
│                                     │
│              ┌─────┐                │
│              │ 🎙️  │                │  big mic button, center
│              └─────┘                │
│                                     │
│         Tap to dictate              │
└─────────────────────────────────────┘
```

States: idle → recording (pulse animation) → transcribing (spinner) → idle/error.

---

## What Transfers From macOS Codebase

| macOS Component | Reusable? | Notes |
|---|---|---|
| Audio recording (AVAudioEngine) | ~70% | Same approach, strip macOS-specific config |
| OpenAI API call | ~90% | Nearly identical URLSession code |
| M4A compression | Yes | AVAssetExportSession works on iOS |
| TranscriptionHistory model | Yes | Move to App Group storage |
| Trial tracking logic | Yes | Same UserDefaults approach, different suite |
| ObfuscatedKey (XOR) | Yes | Platform-independent |
| HotkeyManager | No | Not applicable on iOS |
| OutputDispatcher | No | Replaced by `textDocumentProxy.insertText()` |
| PillView / PillWindow | No | Completely different UI paradigm |

Realistically ~30% code reuse. This is a new app that shares some logic.

---

## Constraints & Gotchas

| Issue | Impact | Mitigation |
|-------|--------|------------|
| **Memory limit (~50-70MB)** | Extension killed if exceeded | Record to disk, not memory. Keep UI lightweight. |
| **"Allow Full Access" required** | Scary Apple warning, users hesitate | Clear onboarding explaining why (mic + network only, no data collection). |
| **No background execution** | Extension killed when keyboard dismissed | Must complete transcription before user switches away. |
| **Mic permission is per-extension** | Separate from main app's permission | User gets a second mic prompt on first keyboard use. |
| **Cold start latency (0.5-1s)** | Keyboard feels slow on first switch | Keep extension binary small, no heavy frameworks. |
| **App Store review** | Apple scrutinizes keyboard extensions | Privacy policy required. "Allow Full Access" triggers extra review. |
| **`hasFullAccess` detection** | Network silently fails without full access | Check `self.hasFullAccess` on load, show setup message if false. |

---

## Key Technical Decisions

- **No on-device ASR** — same as macOS, relies on OpenAI API.
- **Record to file, not memory** — essential for staying under the memory limit.
- **SwiftUI hosted in UIKit** — `UIInputViewController` is UIKit, but the keyboard UI can be SwiftUI via `UIHostingController`.
- **No background transcription** — if the user dismisses the keyboard mid-transcription, it's lost. Accept this limitation.
- **App Group for all shared state** — single source of truth between main app and extension.

---

## Effort Estimate

2-3 weekends for someone comfortable with Swift. More if unfamiliar with extension targets. Main work:

1. Xcode project setup with two targets + App Group (~half day)
2. Main app: onboarding, API key entry, settings (~1 day)
3. Keyboard extension: audio recording + transcription (~1 day)
4. Keyboard UI + state management (~1 day)
5. Testing across apps, edge cases, polish (~1 day)
6. App Store prep: privacy policy, screenshots, review notes (~half day)
