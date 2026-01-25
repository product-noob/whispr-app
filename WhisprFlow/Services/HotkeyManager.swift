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
    
    // MARK: - State
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyPressed = false
    private(set) var currentHotkey: HotkeyType = .controlSpace
    
    // For modifier+key combos
    private var modifiersPressed = false
    private var spacePressed = false
    
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
        
        // Check accessibility permission
        let hasPermission = checkAccessibilityPermission()
        logToFile("[HotkeyManager] Accessibility permission: \(hasPermission)")
        guard hasPermission else {
            logToFile("[HotkeyManager] ERROR: No accessibility permission")
            return false
        }
        
        // Create event tap
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
            logToFile("[HotkeyManager] Run loop source added")
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
    }
    
    func setHotkey(_ type: HotkeyType) {
        currentHotkey = type
        UserDefaults.standard.set(type.rawValue, forKey: "hotkeyType")
        
        // Reset state
        isHotkeyPressed = false
        modifiersPressed = false
        spacePressed = false
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
        if let saved = UserDefaults.standard.string(forKey: "hotkeyType"),
           let type = HotkeyType(rawValue: saved) {
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
    
    private func handleFnKey(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }
        
        let flags = event.flags
        let fnPressed = flags.contains(.maskSecondaryFn)
        
        if fnPressed && !isHotkeyPressed {
            isHotkeyPressed = true
            logToFile("[HotkeyManager] Fn key DOWN")
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyDown?()
            }
        } else if !fnPressed && isHotkeyPressed {
            isHotkeyPressed = false
            logToFile("[HotkeyManager] Fn key UP")
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyUp?()
            }
        }
    }
    
    private func handleModifierSpace(type: CGEventType, event: CGEvent, modifier: CGEventFlags) {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let spaceKeyCode: Int64 = 49
        
        // Check modifier state
        let modifierDown = flags.contains(modifier)
        
        switch type {
        case .flagsChanged:
            modifiersPressed = modifierDown
            
            // If modifier released while space still down, trigger up
            if !modifierDown && isHotkeyPressed {
                isHotkeyPressed = false
                spacePressed = false
                logToFile("[HotkeyManager] Modifier+Space UP (modifier released)")
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyUp?()
                }
            }
            
        case .keyDown:
            if keyCode == spaceKeyCode && modifiersPressed && !isHotkeyPressed {
                spacePressed = true
                isHotkeyPressed = true
                logToFile("[HotkeyManager] Modifier+Space DOWN")
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyDown?()
                }
            }
            
        case .keyUp:
            if keyCode == spaceKeyCode && isHotkeyPressed {
                isHotkeyPressed = false
                spacePressed = false
                logToFile("[HotkeyManager] Modifier+Space UP (space released)")
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyUp?()
                }
            }
            
        default:
            break
        }
    }
    
    private func handleCommandShiftSpace(type: CGEventType, event: CGEvent) {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let spaceKeyCode: Int64 = 49
        
        // Check both command and shift
        let commandDown = flags.contains(.maskCommand)
        let shiftDown = flags.contains(.maskShift)
        let bothModifiersDown = commandDown && shiftDown
        
        switch type {
        case .flagsChanged:
            modifiersPressed = bothModifiersDown
            
            // If either modifier released while space still down, trigger up
            if !bothModifiersDown && isHotkeyPressed {
                isHotkeyPressed = false
                spacePressed = false
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyUp?()
                }
            }
            
        case .keyDown:
            if keyCode == spaceKeyCode && modifiersPressed && !isHotkeyPressed {
                spacePressed = true
                isHotkeyPressed = true
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyDown?()
                }
            }
            
        case .keyUp:
            if keyCode == spaceKeyCode && isHotkeyPressed {
                isHotkeyPressed = false
                spacePressed = false
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyUp?()
                }
            }
            
        default:
            break
        }
    }
}
