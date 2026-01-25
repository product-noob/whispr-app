import AppKit
import SwiftUI

/// Callbacks for pill interactions
struct PillCallbacks {
    var hotkeyManager: HotkeyManager?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?
}

/// A floating panel that displays the pill UI without stealing focus.
/// This window:
/// - Never becomes key or main window
/// - Floats above other windows
/// - Appears on all spaces
/// - Does not activate the app when clicked
final class PillWindow: NSPanel {
    
    private var hostingView: NSHostingView<PillView>?
    
    init(stateManager: AppStateManager, callbacks: PillCallbacks = PillCallbacks()) {
        // Larger frame to accommodate expanded state
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configure()
        setupContent(stateManager: stateManager, callbacks: callbacks)
        positionAtBottomCenter()
    }
    
    private func configure() {
        // Window level - float above normal windows
        level = .floating
        
        // Appear on all spaces and stay put
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        
        // Visual properties
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // We'll add shadow in SwiftUI
        
        // Never steal focus
        isMovableByWindowBackground = false
        
        // Keep visible
        hidesOnDeactivate = false
    }
    
    private func setupContent(stateManager: AppStateManager, callbacks: PillCallbacks) {
        let pillView = PillView(
            stateManager: stateManager,
            hotkeyManager: callbacks.hotkeyManager ?? HotkeyManager(),
            onStartRecording: callbacks.onStartRecording,
            onStopRecording: callbacks.onStopRecording,
            onCancelRecording: callbacks.onCancelRecording,
            onRetry: callbacks.onRetry,
            onDiscard: callbacks.onDiscard,
            onOpenSettings: callbacks.onOpenSettings,
            onOpenHistory: callbacks.onOpenHistory
        )
        let hosting = NSHostingView(rootView: pillView)
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        hostingView = hosting
    }
    
    /// Position the window at the bottom center of the main screen
    func positionAtBottomCenter() {
        // Use the screen where the mouse is, or fall back to main screen
        let mouseLocation = NSEvent.mouseLocation
        var targetScreen = NSScreen.main
        
        for screen in NSScreen.screens {
            if NSMouseInRect(mouseLocation, screen.frame, false) {
                targetScreen = screen
                break
            }
        }
        
        guard let screen = targetScreen else {
            logToFile("[PillWindow] ERROR: No screen found")
            return
        }
        
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 80
        
        // Center horizontally using the screen's frame
        let x = screenFrame.origin.x + (screenFrame.width / 2) - (windowWidth / 2)
        
        // Position at bottom - 40 pixels above the visible frame bottom (above dock)
        // visibleFrame.minY is the bottom of the usable area (above dock if dock is at bottom)
        let y = visibleFrame.minY + 40
        
        logToFile("[PillWindow] All screens: \(NSScreen.screens.map { "(\($0.frame))" }.joined(separator: ", "))")
        logToFile("[PillWindow] Target screen frame: \(screenFrame)")
        logToFile("[PillWindow] Visible frame: \(visibleFrame)")
        logToFile("[PillWindow] Final position: x=\(Int(x)), y=\(Int(y))")
        
        setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }
    
    // MARK: - Prevent Focus Stealing
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    // Allow clicks to pass through to the SwiftUI content
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
    }
}

// MARK: - Window Controller

final class PillWindowController: NSWindowController {
    
    convenience init(stateManager: AppStateManager, callbacks: PillCallbacks = PillCallbacks()) {
        let window = PillWindow(stateManager: stateManager, callbacks: callbacks)
        self.init(window: window)
    }
    
    func show() {
        window?.orderFrontRegardless()
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    func reposition() {
        (window as? PillWindow)?.positionAtBottomCenter()
    }
}
