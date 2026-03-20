import AppKit
import Carbon
import Foundation

/// Manages global hotkey detection with configurable triggers
final class HotkeyManager {

    // MARK: - Types

    enum HotkeyType: String, CaseIterable, Codable {
        case fnKey = "fn"
        case controlSpace = "ctrl+space"
        case optionSpace = "opt+space"
        case commandShiftSpace = "cmd+shift+space"

        var displayName: String {
            switch self {
            case .fnKey: return "Fn Key"
            case .controlSpace: return "Control + Space"
            case .optionSpace: return "Option + Space"
            case .commandShiftSpace: return "Cmd + Shift + Space"
            }
        }
    }

    // MARK: - Callbacks

    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var onHandsFreeStart: (() -> Void)?
    var onHandsFreeStop: (() -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyPressed = false
    private(set) var currentHotkey: HotkeyType = .fnKey

    // For modifier+key combos
    private var modifiersPressed = false
    private var spacePressed = false

    // Double-tap hands-free state
    private var lastHotkeyUpTime: Date = .distantPast
    private var lastTapWasShort = false
    private(set) var isHandsFreeActive = false
    private let doubleTapWindow: TimeInterval = 0.35
    private var hotkeyDownTime: Date = .distantPast

    // MARK: - Initialization

    init() {
        loadSavedHotkey()
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    func start() -> Bool {
        logToFile("[HotkeyManager] start() called, current hotkey: \(currentHotkey.displayName)")

        guard eventTap == nil else {
            logToFile("[HotkeyManager] Event tap already exists")
            return true
        }

        let hasPermission = checkAccessibilityPermission()
        logToFile("[HotkeyManager] Accessibility permission: \(hasPermission)")
        guard hasPermission else {
            logToFile("[HotkeyManager] ERROR: No accessibility permission")
            return false
        }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logToFile("[HotkeyManager] ERROR: Failed to create event tap")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        logToFile("[HotkeyManager] Event tap enabled successfully")

        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isHotkeyPressed = false
        modifiersPressed = false
        spacePressed = false
        isHandsFreeActive = false
    }

    func setHotkey(_ type: HotkeyType) {
        currentHotkey = type
        ConfigStore.shared.update { $0.hotkeyType = type.rawValue }

        isHotkeyPressed = false
        modifiersPressed = false
        spacePressed = false
        isHandsFreeActive = false
    }

    // MARK: - Permission

    func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Private Methods

    private func loadSavedHotkey() {
        if let type = HotkeyType(rawValue: ConfigStore.shared.config.hotkeyType) {
            currentHotkey = type
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Escape to cancel (keycode 53)
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 {
                if isHandsFreeActive {
                    isHandsFreeActive = false
                    DispatchQueue.main.async { [weak self] in self?.onCancel?() }
                    return Unmanaged.passRetained(event)
                }
                if isHotkeyPressed {
                    isHotkeyPressed = false
                    DispatchQueue.main.async { [weak self] in self?.onCancel?() }
                    return Unmanaged.passRetained(event)
                }
            }

            // Any non-escape keyDown stops hands-free mode
            if isHandsFreeActive && keyCode != 53 {
                isHandsFreeActive = false
                DispatchQueue.main.async { [weak self] in self?.onHandsFreeStop?() }
                return Unmanaged.passRetained(event)
            }
        }

        switch currentHotkey {
        case .fnKey:
            handleFnKey(type: type, event: event)
        case .controlSpace:
            handleModifierSpace(type: type, event: event, modifier: .maskControl)
        case .optionSpace:
            handleModifierSpace(type: type, event: event, modifier: .maskAlternate)
        case .commandShiftSpace:
            handleCommandShiftSpace(type: type, event: event)
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Double-Tap Detection

    private func handleHotkeyDown() {
        // Check for double-tap
        if ConfigStore.shared.config.doubleTapHandsFree,
           lastTapWasShort,
           Date().timeIntervalSince(lastHotkeyUpTime) < doubleTapWindow {
            isHandsFreeActive = true
            lastTapWasShort = false
            logToFile("[HotkeyManager] Double-tap detected — hands-free mode START")
            DispatchQueue.main.async { [weak self] in self?.onHandsFreeStart?() }
            return
        }

        hotkeyDownTime = Date()
        isHotkeyPressed = true
        logToFile("[HotkeyManager] Hotkey DOWN")
        DispatchQueue.main.async { [weak self] in self?.onHotkeyDown?() }
    }

    private func handleHotkeyUp() {
        if isHandsFreeActive { return }

        isHotkeyPressed = false

        // Track short taps for double-tap detection (< 300ms)
        let tapDuration = Date().timeIntervalSince(hotkeyDownTime)
        lastTapWasShort = tapDuration < 0.3
        lastHotkeyUpTime = Date()

        logToFile("[HotkeyManager] Hotkey UP (duration: \(String(format: "%.0f", tapDuration * 1000))ms)")
        DispatchQueue.main.async { [weak self] in self?.onHotkeyUp?() }
    }

    // MARK: - Hotkey Handlers

    private func handleFnKey(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }

        let flags = event.flags
        let fnPressed = flags.contains(.maskSecondaryFn)

        if fnPressed && !isHotkeyPressed && !isHandsFreeActive {
            handleHotkeyDown()
        } else if !fnPressed && isHotkeyPressed {
            handleHotkeyUp()
        }
    }

    private func handleModifierSpace(type: CGEventType, event: CGEvent, modifier: CGEventFlags) {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let spaceKeyCode: Int64 = 49
        let modifierDown = flags.contains(modifier)

        switch type {
        case .flagsChanged:
            modifiersPressed = modifierDown
            if !modifierDown && isHotkeyPressed {
                spacePressed = false
                handleHotkeyUp()
            }

        case .keyDown:
            if keyCode == spaceKeyCode && modifiersPressed && !isHotkeyPressed && !isHandsFreeActive {
                spacePressed = true
                handleHotkeyDown()
            }

        case .keyUp:
            if keyCode == spaceKeyCode && isHotkeyPressed {
                spacePressed = false
                handleHotkeyUp()
            }

        default:
            break
        }
    }

    private func handleCommandShiftSpace(type: CGEventType, event: CGEvent) {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let spaceKeyCode: Int64 = 49
        let bothModifiersDown = flags.contains(.maskCommand) && flags.contains(.maskShift)

        switch type {
        case .flagsChanged:
            modifiersPressed = bothModifiersDown
            if !bothModifiersDown && isHotkeyPressed {
                spacePressed = false
                handleHotkeyUp()
            }

        case .keyDown:
            if keyCode == spaceKeyCode && modifiersPressed && !isHotkeyPressed && !isHandsFreeActive {
                spacePressed = true
                handleHotkeyDown()
            }

        case .keyUp:
            if keyCode == spaceKeyCode && isHotkeyPressed {
                spacePressed = false
                handleHotkeyUp()
            }

        default:
            break
        }
    }
}
