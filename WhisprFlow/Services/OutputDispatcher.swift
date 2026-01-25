import AppKit
import Carbon

/// Handles text output via clipboard and paste simulation
final class OutputDispatcher {
    
    enum OutputMode: String, CaseIterable, Codable {
        case paste = "paste"
        case clipboardOnly = "clipboard"
        
        var displayName: String {
            switch self {
            case .paste: return "Auto-paste"
            case .clipboardOnly: return "Copy to clipboard only"
            }
        }
    }
    
    enum OutputResult {
        case pasteAttempted
        case clipboardOnly
        case debounced
        case failed(String)
    }
    
    private var lastPasteTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.5
    
    var outputMode: OutputMode {
        get {
            if let saved = UserDefaults.standard.string(forKey: "outputMode"),
               let mode = OutputMode(rawValue: saved) {
                return mode
            }
            return .paste
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "outputMode")
        }
    }
    
    /// Insert text using the configured output mode
    func insertText(_ text: String) -> OutputResult {
        let now = Date()
        
        // Debounce check
        guard now.timeIntervalSince(lastPasteTime) >= debounceInterval else {
            return .debounced
        }
        lastPasteTime = now
        
        // Copy to clipboard first
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        guard pasteboard.setString(text, forType: .string) else {
            return .failed("Could not write to clipboard")
        }
        
        // If clipboard only mode, we're done
        guard outputMode == .paste else {
            return .clipboardOnly
        }
        
        // Small delay to ensure clipboard is ready
        Thread.sleep(forTimeInterval: 0.05)
        
        // Simulate Cmd+V
        guard simulatePaste() else {
            return .clipboardOnly // Fallback - text is still in clipboard
        }
        
        return .pasteAttempted
    }
    
    /// Copy text to clipboard without pasting
    func copyToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
    
    // MARK: - Private
    
    private func simulatePaste() -> Bool {
        // V key virtual keycode
        let vKeyCode: CGKeyCode = 9
        
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }
        
        // Create key down event with Command modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            return false
        }
        keyDown.flags = .maskCommand
        
        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return false
        }
        keyUp.flags = .maskCommand
        
        // Post events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        return true
    }
}
