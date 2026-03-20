import AppKit
import SwiftUI

/// Callbacks for pill interactions
struct PillCallbacks {
    var hotkeyManager: HotkeyManager?
    var audioRecorder: AudioRecorder?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onCancelTranscription: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?
}

/// A floating panel that displays the pill UI without stealing focus.
/// Window stays a fixed size — the SwiftUI pill content resizes visually within it.
final class PillWindow: NSPanel {

    private var hostingView: NSHostingView<PillView>?
    private var dragOrigin: NSPoint?
    private var isDragging = false

    /// Fixed window size — large enough to contain all pill states without resizing
    private static let windowSize = NSSize(width: 320, height: 90)

    init(stateManager: AppStateManager, callbacks: PillCallbacks = PillCallbacks()) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configure()
        setupContent(stateManager: stateManager, callbacks: callbacks)
        restoreOrDefaultPosition()
    }

    private func configure() {
        level = .init(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    private func setupContent(stateManager: AppStateManager, callbacks: PillCallbacks) {
        let pillView = PillView(
            stateManager: stateManager,
            hotkeyManager: callbacks.hotkeyManager ?? HotkeyManager(),
            audioRecorder: callbacks.audioRecorder,
            onStartRecording: callbacks.onStartRecording,
            onStopRecording: callbacks.onStopRecording,
            onCancelRecording: callbacks.onCancelRecording,
            onCancelTranscription: callbacks.onCancelTranscription,
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

    // MARK: - Dragging (via sendEvent since canBecomeKey is false)

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragOrigin = event.locationInWindow
            super.sendEvent(event)

        case .leftMouseDragged:
            if let origin = dragOrigin {
                let current = event.locationInWindow
                let dx = current.x - origin.x
                let dy = current.y - origin.y
                let distance = sqrt(dx * dx + dy * dy)

                if !isDragging && distance < 3 {
                    super.sendEvent(event)
                } else {
                    if !isDragging {
                        isDragging = true
                        animator().alphaValue = 0.6
                    }
                    let delta = NSPoint(x: dx, y: dy)
                    let newOrigin = NSPoint(x: frame.origin.x + delta.x, y: frame.origin.y + delta.y)
                    setFrameOrigin(newOrigin)
                }
            } else {
                super.sendEvent(event)
            }

        case .leftMouseUp:
            if isDragging {
                animator().alphaValue = 1.0
                ConfigStore.shared.update {
                    $0.pillPosition = CodablePoint(x: Double(frame.midX), y: Double(frame.midY))
                }
                dragOrigin = nil
                isDragging = false
            } else {
                dragOrigin = nil
                isDragging = false
                super.sendEvent(event)
            }

        default:
            super.sendEvent(event)
        }
    }

    // MARK: - Positioning

    func restoreOrDefaultPosition() {
        if let saved = ConfigStore.shared.config.pillPosition, let screen = NSScreen.main {
            let origin = NSPoint(
                x: CGFloat(saved.x) - frame.width / 2,
                y: CGFloat(saved.y) - frame.height / 2
            )
            let clamped = NSPoint(
                x: max(screen.frame.minX, min(origin.x, screen.frame.maxX - frame.width)),
                y: max(screen.frame.minY, min(origin.y, screen.frame.maxY - frame.height))
            )
            setFrameOrigin(clamped)
        } else {
            positionAtBottomCenter()
        }
    }

    func positionAtBottomCenter() {
        let mouseLocation = NSEvent.mouseLocation
        var targetScreen = NSScreen.main

        for screen in NSScreen.screens {
            if NSMouseInRect(mouseLocation, screen.frame, false) {
                targetScreen = screen
                break
            }
        }

        guard let screen = targetScreen else { return }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let size = frame.size

        let x = screenFrame.origin.x + (screenFrame.width / 2) - (size.width / 2)
        let y = visibleFrame.minY + 15

        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    // MARK: - Prevent Focus Stealing

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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
        (window as? PillWindow)?.restoreOrDefaultPosition()
    }
}
