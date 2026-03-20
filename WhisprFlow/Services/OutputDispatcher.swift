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
            OutputMode(rawValue: ConfigStore.shared.config.outputMode) ?? .paste
        }
        set {
            ConfigStore.shared.update { $0.outputMode = newValue.rawValue }
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

        // F10: Smart paste spacing — prepend space if needed
        var finalText = text
        if ConfigStore.shared.config.smartSpacing {
            finalText = applySmartSpacing(text)
        }

        // Copy to clipboard first
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.setString(finalText, forType: .string) else {
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

    // MARK: - F10: Smart Paste Spacing

    /// Attempts to prepend a space if the cursor is adjacent to existing text.
    /// Uses Accessibility API to detect context; falls back to always-prepend heuristic.
    private func applySmartSpacing(_ text: String) -> String {
        // Try to get the character before cursor via Accessibility API
        if let charBefore = characterBeforeCursor() {
            // If preceding char is a letter, digit, or closing punctuation → prepend space
            if charBefore.isLetter || charBefore.isNumber || [")", "\"", "'", "\u{201D}", "\u{2019}"].contains(String(charBefore)) {
                return " " + text
            }
            // If it's a space, newline, opening bracket, or position 0 → no space
            return text
        }

        // Fallback heuristic: always prepend a space (correct ~80% of the time)
        return " " + text
    }

    /// Uses Accessibility API to read the character before the cursor in the focused text field.
    /// Returns nil if accessibility is unavailable or the field doesn't expose its value.
    private func characterBeforeCursor() -> Character? {
        guard let focusedElement = getFocusedTextElement() else { return nil }

        // Get the text value
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &valueRef)
        guard valueResult == .success, let value = valueRef as? String, !value.isEmpty else { return nil }

        // Get selected text range (insertion point)
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard rangeResult == .success, let rangeValue = rangeRef else { return nil }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange) else { return nil }

        // Get the character before the insertion point
        let insertionPoint = cfRange.location
        guard insertionPoint > 0, insertionPoint <= value.count else {
            if insertionPoint == 0 { return "\n" } // Signal: at start, no space needed
            return nil
        }

        let index = value.index(value.startIndex, offsetBy: insertionPoint - 1)
        return value[index]
    }

    /// Gets the focused text element via Accessibility API
    private func getFocusedTextElement() -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()

        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedApplicationAttribute as CFString, &focusedAppRef) == .success else {
            return nil
        }

        let focusedApp = focusedAppRef as! AXUIElement

        var focusedElementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedApp, kAXFocusedUIElementAttribute as CFString, &focusedElementRef) == .success else {
            return nil
        }

        return (focusedElementRef as! AXUIElement)
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
