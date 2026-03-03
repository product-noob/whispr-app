import AppKit
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.whisprflow.app", category: "AppDelegate")

// File-based logging for debugging
func logToFile(_ message: String) {
    let logPath = "/tmp/whisprflow_debug.log"
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let logMessage = "[\(timestamp)] \(message)\n"
    
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(logMessage.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: logMessage.data(using: .utf8))
    }
}

/// AppDelegate handles AppKit-level lifecycle events and coordinates all services.
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Services
    
    private let stateManager = AppStateManager()
    private let audioRecorder = AudioRecorder()
    private let transcriptionManager = TranscriptionManager()
    private let hotkeyManager = HotkeyManager()
    private let outputDispatcher = OutputDispatcher()
    private let historyStore = HistoryStore()
    
    // MARK: - Windows
    
    private var pillWindowController: PillWindowController?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var addAPIKeyWindowController: AddAPIKeyWindowController?
    
    // MARK: - Menu Bar
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logToFile("=== WhisprFlow Starting ===")
        setupApp()
        setupHotkeys()
        setupMenuBar()
        showPillWindow()
        observeScreenChanges()
        checkInitialPermissions()
        logToFile("=== WhisprFlow Started ===")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    
    // MARK: - Setup
    
    private func setupApp() {
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupMenuBar() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Try to load custom icon, fallback to SF Symbol
            if let iconImage = NSImage(named: "MenuBarIcon") {
                iconImage.size = NSSize(width: 18, height: 18)
                iconImage.isTemplate = false  // Use original colors
                button.image = iconImage
            } else {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Whispr")
            }
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 420)
        popover?.behavior = .transient
        popover?.animates = true
        
        let menuBarView = MenuBarView(
            stateManager: stateManager,
            hotkeyManager: hotkeyManager,
            outputDispatcher: outputDispatcher,
            historyStore: historyStore,
            onStartRecording: { [weak self] in
                self?.popover?.close()
                self?.startRecording()
            },
            onOpenSettings: { [weak self] in
                self?.popover?.close()
                self?.openSettings()
            },
            onOpenHistory: { [weak self] in
                self?.popover?.close()
                self?.openHistory()
            }
        )
        popover?.contentViewController = NSHostingController(rootView: menuBarView)
    }
    
    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Ensure popover window doesn't steal focus from other apps when just viewing
            popover.contentViewController?.view.window?.level = .floating
        }
    }
    
    /// Update the menu bar icon based on recording state
    private func updateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem?.button else { return }
        
        if isRecording {
            // Use a recording indicator (red dot or waveform.badge.mic)
            if let recordingImage = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "Recording") {
                recordingImage.isTemplate = false
                button.image = recordingImage
            }
        } else {
            // Reset to default icon
            if let iconImage = NSImage(named: "MenuBarIcon") {
                iconImage.size = NSSize(width: 18, height: 18)
                iconImage.isTemplate = false
                button.image = iconImage
            } else {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Whispr")
            }
        }
    }
    
    private func setupHotkeys() {
        logToFile("Setting up hotkeys with type: \(hotkeyManager.currentHotkey.displayName)")
        
        hotkeyManager.onHotkeyDown = { [weak self] in
            logToFile("Hotkey DOWN detected - starting recording")
            self?.startRecording()
        }
        
        hotkeyManager.onHotkeyUp = { [weak self] in
            logToFile("Hotkey UP detected - stopping recording")
            self?.stopRecording()
        }
        
        // Start hotkey monitoring
        let started = hotkeyManager.start()
        logToFile("Hotkey manager started: \(started)")
        if !started {
            logToFile("ERROR: Failed to start hotkey manager - accessibility permission may be needed")
        }
    }
    
    private func showPillWindow() {
        let callbacks = PillCallbacks(
            hotkeyManager: hotkeyManager,
            onStartRecording: { [weak self] in self?.startRecording() },
            onStopRecording: { [weak self] in self?.stopRecording() },
            onCancelRecording: { [weak self] in self?.cancelRecording() },
            onRetry: { [weak self] in self?.retryTranscription() },
            onDiscard: { [weak self] in self?.discardRecording() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenHistory: { [weak self] in self?.openHistory() }
        )
        
        pillWindowController = PillWindowController(stateManager: stateManager, callbacks: callbacks)
        pillWindowController?.show()
    }
    
    private func checkInitialPermissions() {
        logToFile("Checking initial permissions...")
        
        // Check microphone permission
        Task {
            let hasPermission = await audioRecorder.requestPermission()
            logToFile("Microphone permission: \(hasPermission)")
            if !hasPermission {
                await MainActor.run {
                    stateManager.setError(.microphonePermissionDenied)
                    scheduleErrorRecovery()
                }
            }
        }
        
        // Check accessibility permission
        let hasAccessibility = hotkeyManager.hasAccessibilityPermission
        logToFile("Accessibility permission: \(hasAccessibility)")
        if !hasAccessibility {
            logToFile("Requesting accessibility permission...")
            _ = hotkeyManager.checkAccessibilityPermission() // This prompts the user
            
            // Start polling for accessibility permission to restart hotkey manager when granted
            startAccessibilityPermissionPolling()
        }
        
        // Check API key / trial status
        let trialTracker = TrialTracker.shared
        logToFile("Trial active: \(trialTracker.isTrialActive), Has user key: \(KeychainHelper.hasAPIKey)")
        logToFile("Trial status: \(trialTracker.trialStatusMessage)")
        
        // Only prompt if trial ended and no user key
        if trialTracker.shouldShowAddKeyPrompt {
            logToFile("Trial ended, showing add API key prompt...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.showAddAPIKeyPrompt()
            }
        }
    }
    
    /// Poll for accessibility permission and restart hotkey manager when granted
    private func startAccessibilityPermissionPolling() {
        // Check every 2 seconds for up to 60 seconds
        var attempts = 0
        let maxAttempts = 30
        
        func checkAndRetry() {
            attempts += 1
            if hotkeyManager.hasAccessibilityPermission {
                logToFile("Accessibility permission now granted, restarting hotkey manager...")
                let started = hotkeyManager.start()
                logToFile("Hotkey manager restarted: \(started)")
            } else if attempts < maxAttempts {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    checkAndRetry()
                }
            } else {
                logToFile("Accessibility permission polling timed out after \(maxAttempts) attempts")
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            checkAndRetry()
        }
    }
    
    /// Schedule automatic recovery from error state after a delay
    private func scheduleErrorRecovery() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self else { return }
            // Only reset if still in error state
            if case .error = self.stateManager.state {
                logToFile("Auto-recovering from error state to idle")
                self.stateManager.reset()
            }
        }
    }
    
    // MARK: - Screen Changes
    
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func screenParametersChanged() {
        pillWindowController?.reposition()
    }
    
    // MARK: - Recording Flow
    
    private func startRecording() {
        print("[WhisprFlow] startRecording() called")
        print("[WhisprFlow] - canStartRecording: \(stateManager.canStartRecording)")
        print("[WhisprFlow] - current state: \(stateManager.state)")
        
        guard stateManager.canStartRecording else {
            print("[WhisprFlow] Cannot start recording - state doesn't allow it")
            return
        }
        
        // Check permissions first
        guard audioRecorder.hasPermission else {
            print("[WhisprFlow] ERROR: No microphone permission")
            stateManager.setError(.microphonePermissionDenied)
            scheduleErrorRecovery()
            return
        }
        
        // Check if we can transcribe (trial active OR user has own key)
        guard TrialTracker.shared.canTranscribe else {
            print("[WhisprFlow] ERROR: Trial ended and no API key configured")
            stateManager.setError(.noAPIKey)
            scheduleErrorRecovery()
            showAddAPIKeyPrompt()
            return
        }
        
        do {
            let url = try audioRecorder.startRecording()
            print("[WhisprFlow] Recording started, saving to: \(url.path)")
            stateManager.startRecording()
            updateMenuBarIcon(isRecording: true)
        } catch {
            print("[WhisprFlow] ERROR starting recording: \(error.localizedDescription)")
            stateManager.setError(.recordingFailed(error.localizedDescription))
            scheduleErrorRecovery()
        }
    }
    
    private func stopRecording() {
        print("[WhisprFlow] stopRecording() called")
        print("[WhisprFlow] - canStopRecording: \(stateManager.canStopRecording)")
        print("[WhisprFlow] - current state: \(stateManager.state)")
        
        guard stateManager.canStopRecording else {
            print("[WhisprFlow] Cannot stop recording - not currently recording")
            return
        }
        
        // Reset menu bar icon immediately when user releases hotkey
        updateMenuBarIcon(isRecording: false)
        
        // Use Task to handle async stopRecording (which includes buffer flush delay)
        Task {
            do {
                let audioURL = try await audioRecorder.stopRecording()
                print("[WhisprFlow] Recording stopped, file at: \(audioURL.path)")
                
                await MainActor.run {
                    stateManager.stopRecording(audioURL: audioURL)
                    
                    // Start transcription
                    print("[WhisprFlow] Starting transcription...")
                    transcribe(audioURL: audioURL)
                }
            } catch {
                print("[WhisprFlow] ERROR stopping recording: \(error.localizedDescription)")
                await MainActor.run {
                    stateManager.setError(.recordingFailed(error.localizedDescription))
                    scheduleErrorRecovery()
                }
            }
        }
    }
    
    private func cancelRecording() {
        audioRecorder.cancelRecording()
        stateManager.cancelRecording()
        updateMenuBarIcon(isRecording: false)
    }
    
    // MARK: - Transcription Flow
    
    private func transcribe(audioURL: URL) {
        print("[WhisprFlow] transcribe() called for: \(audioURL.lastPathComponent)")
        logToFile("[AppDelegate] Starting transcription for: \(audioURL.lastPathComponent)")
        
        Task {
            do {
                // Step 1: Optionally compress audio (skip for small files for speed)
                let finalURL: URL
                if audioRecorder.shouldCompress(fileURL: audioURL) {
                    logToFile("[AppDelegate] Compressing audio to M4A...")
                    do {
                        finalURL = try await audioRecorder.compressToM4A(wavURL: audioURL)
                        logToFile("[AppDelegate] Compression successful: \(finalURL.lastPathComponent)")
                    } catch {
                        // If compression fails, use original WAV
                        logToFile("[AppDelegate] Compression failed, using original WAV: \(error.localizedDescription)")
                        finalURL = audioURL
                    }
                } else {
                    logToFile("[AppDelegate] Skipping compression for small file")
                    finalURL = audioURL
                }
                
                // Step 2: Transcribe
                print("[WhisprFlow] Calling transcription API...")
                logToFile("[AppDelegate] Calling transcription API...")
                let text = try await transcriptionManager.transcribe(audioURL: finalURL)
                print("[WhisprFlow] Transcription SUCCESS: \"\(text.prefix(50))...\"")
                logToFile("[AppDelegate] Transcription SUCCESS: \(text.count) characters")
                
                // Cleanup audio file
                try? FileManager.default.removeItem(at: finalURL)
                
                await MainActor.run {
                    stateManager.transcriptionSucceeded(text: text)
                    
                    // Save to history
                    historyStore.addEntry(text)
                    
                    insertText(text)
                }
            } catch let error as TranscriptionManager.TranscriptionError {
                print("[WhisprFlow] Transcription ERROR: \(error.localizedDescription)")
                logToFile("[AppDelegate] Transcription ERROR: \(error.localizedDescription)")
                await MainActor.run {
                    switch error {
                    case .noAPIKey:
                        stateManager.transcriptionFailed(error: .noAPIKey)
                    case .trialEnded:
                        stateManager.transcriptionFailed(error: .noAPIKey)
                        showAddAPIKeyPrompt()
                    case .invalidAPIKey:
                        stateManager.transcriptionFailed(error: .invalidAPIKey)
                    case .timeout:
                        stateManager.transcriptionFailed(error: .transcriptionTimeout)
                    case .emptyTranscription:
                        stateManager.transcriptionFailed(error: .emptyTranscription)
                    case .networkError(let msg):
                        stateManager.transcriptionFailed(error: .networkError(msg))
                    default:
                        stateManager.transcriptionFailed(error: .transcriptionFailed(error.localizedDescription))
                    }
                    scheduleErrorRecovery()
                }
            } catch {
                print("[WhisprFlow] Transcription UNEXPECTED ERROR: \(error.localizedDescription)")
                logToFile("[AppDelegate] Transcription UNEXPECTED ERROR: \(error.localizedDescription)")
                await MainActor.run {
                    stateManager.transcriptionFailed(error: .transcriptionFailed(error.localizedDescription))
                    scheduleErrorRecovery()
                }
            }
        }
    }
    
    private func retryTranscription() {
        guard stateManager.canRetry, let audioURL = stateManager.currentRecordingURL else { return }
        stateManager.retry()
        transcribe(audioURL: audioURL)
    }
    
    private func discardRecording() {
        // Delete the audio file
        if let url = stateManager.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        stateManager.discard()
    }
    
    // MARK: - Output
    
    private func insertText(_ text: String) {
        let result = outputDispatcher.insertText(text)
        
        switch result {
        case .pasteAttempted:
            break // Success, no notification needed
        case .clipboardOnly:
            // Show notification that text is in clipboard
            showNotification("Copied to clipboard")
        case .debounced:
            break // Ignored
        case .failed(let reason):
            showNotification("Paste failed: \(reason)")
        }
    }
    
    private func showNotification(_ message: String) {
        // Could use NSUserNotification or just log for now
        print("Notification: \(message)")
    }
    
    // MARK: - Add API Key Prompt
    
    private func showAddAPIKeyPrompt() {
        if addAPIKeyWindowController == nil {
            addAPIKeyWindowController = AddAPIKeyWindowController(onKeyAdded: { [weak self] in
                logToFile("[AppDelegate] User added their API key")
                self?.addAPIKeyWindowController = nil
            })
        }
        addAPIKeyWindowController?.show()
    }
    
    // MARK: - Settings
    
    private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView(
                hotkeyManager: hotkeyManager,
                outputDispatcher: outputDispatcher,
                onSave: { [weak self] in
                    // Restart hotkey manager with new settings
                    self?.hotkeyManager.stop()
                    _ = self?.hotkeyManager.start()
                }
            )
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Whispr Settings"
            window.contentView = NSHostingView(rootView: settingsView)
            window.center()
            window.isReleasedWhenClosed = false
            
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - History
    
    private func openHistory() {
        if historyWindow == nil {
            let historyView = HistoryView(
                historyStore: historyStore,
                hotkeyManager: hotkeyManager,
                outputDispatcher: outputDispatcher,
                onStartRecording: { [weak self] in
                    self?.historyWindow?.close()
                    self?.startRecording()
                },
                onClose: { [weak self] in
                    self?.historyWindow?.close()
                }
            )
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Whispr"
            window.contentView = NSHostingView(rootView: historyView)
            window.center()
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 700, height: 500)
            
            historyWindow = window
        }
        
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
