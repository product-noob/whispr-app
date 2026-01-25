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
    private let realtimeTranscriber = RealtimeTranscriber()
    
    // MARK: - Windows
    
    private var pillWindowController: PillWindowController?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    
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
                iconImage.isTemplate = true
                button.image = iconImage
            } else {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "WhisprFlow")
            }
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 500, height: 400)
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
                }
            }
        }
        
        // Check accessibility permission
        let hasAccessibility = hotkeyManager.hasAccessibilityPermission
        logToFile("Accessibility permission: \(hasAccessibility)")
        if !hasAccessibility {
            logToFile("Requesting accessibility permission...")
            _ = hotkeyManager.checkAccessibilityPermission() // This prompts the user
        }
        
        // Check for API key
        let hasAPIKey = KeychainHelper.hasAPIKey
        logToFile("API key configured: \(hasAPIKey)")
        if !hasAPIKey {
            logToFile("Opening settings for API key setup...")
            // Open settings on first run
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.openSettings()
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
            return
        }
        
        guard KeychainHelper.hasAPIKey else {
            print("[WhisprFlow] ERROR: No API key configured")
            stateManager.setError(.noAPIKey)
            openSettings()
            return
        }
        
        // Check transcription mode
        let mode = TranscriptionMode.current
        logToFile("[AppDelegate] Starting recording in \(mode.displayName) mode")
        
        if mode == .fast {
            startFastModeRecording()
        } else {
            startStandardModeRecording()
        }
    }
    
    private func startStandardModeRecording() {
        do {
            let url = try audioRecorder.startRecording()
            print("[WhisprFlow] Recording started (standard mode), saving to: \(url.path)")
            stateManager.isFastMode = false
            stateManager.startRecording()
        } catch {
            print("[WhisprFlow] ERROR starting recording: \(error.localizedDescription)")
            stateManager.setError(.recordingFailed(error.localizedDescription))
        }
    }
    
    private func startFastModeRecording() {
        Task {
            do {
                // Connect to realtime API
                logToFile("[AppDelegate] Connecting to Realtime API...")
                try await realtimeTranscriber.connect()
                
                // Setup callbacks
                realtimeTranscriber.onPartialTranscript = { [weak self] transcript in
                    DispatchQueue.main.async {
                        self?.stateManager.updatePartialTranscript(transcript)
                    }
                }
                
                realtimeTranscriber.onError = { [weak self] error in
                    logToFile("[AppDelegate] Realtime error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.stateManager.setError(.transcriptionFailed(error.localizedDescription))
                    }
                }
                
                // Setup audio streaming
                audioRecorder.onAudioChunk = { [weak self] chunk in
                    self?.realtimeTranscriber.sendAudioChunk(chunk)
                }
                
                // Start streaming recording
                try audioRecorder.startStreamingRecording()
                
                await MainActor.run {
                    stateManager.isFastMode = true
                    stateManager.clearPartialTranscript()
                    stateManager.startRecording()
                }
                
                logToFile("[AppDelegate] Fast mode recording started")
                
            } catch {
                logToFile("[AppDelegate] Failed to start fast mode: \(error.localizedDescription)")
                await MainActor.run {
                    stateManager.setError(.recordingFailed(error.localizedDescription))
                }
            }
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
        
        if stateManager.isFastMode {
            stopFastModeRecording()
        } else {
            stopStandardModeRecording()
        }
    }
    
    private func stopStandardModeRecording() {
        do {
            let audioURL = try audioRecorder.stopRecording()
            print("[WhisprFlow] Recording stopped, file at: \(audioURL.path)")
            stateManager.stopRecording(audioURL: audioURL)
            
            // Start transcription
            print("[WhisprFlow] Starting transcription...")
            transcribe(audioURL: audioURL)
        } catch {
            print("[WhisprFlow] ERROR stopping recording: \(error.localizedDescription)")
            stateManager.setError(.recordingFailed(error.localizedDescription))
        }
    }
    
    private func stopFastModeRecording() {
        logToFile("[AppDelegate] Stopping fast mode recording...")
        
        // Stop streaming audio first
        audioRecorder.stopStreamingRecording()
        audioRecorder.onAudioChunk = nil
        
        // Clear error callback BEFORE signaling end to prevent race conditions
        // (server errors from endAudio() should not affect app state)
        realtimeTranscriber.onError = nil
        
        // Signal end of audio (commits the buffer)
        realtimeTranscriber.endAudio()
        
        // Give time for final transcripts to arrive (500ms should be enough for server processing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Clear partial transcript callback
            self.realtimeTranscriber.onPartialTranscript = nil
            
            // Get final transcript
            let finalTranscript = self.realtimeTranscriber.getCurrentTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
            
            logToFile("[AppDelegate] Fast mode final transcript (\(finalTranscript.count) chars): \(finalTranscript.prefix(100))...")
            
            // Disconnect
            self.realtimeTranscriber.disconnect()
            
            // Update state FIRST
            self.stateManager.isFastMode = false
            self.stateManager.clearPartialTranscript()
            
            if finalTranscript.isEmpty {
                logToFile("[AppDelegate] Fast mode: empty transcript, setting error")
                self.stateManager.setError(.emptyTranscription)
            } else {
                logToFile("[AppDelegate] Fast mode: success, transitioning to idle")
                // Success!
                self.stateManager.transcriptionSucceeded(text: finalTranscript)
                self.historyStore.addEntry(finalTranscript)
                self.insertText(finalTranscript)
                logToFile("[AppDelegate] Fast mode: state after success: \(self.stateManager.state)")
            }
        }
    }
    
    private func cancelRecording() {
        if stateManager.isFastMode {
            // Clear callbacks first
            realtimeTranscriber.onPartialTranscript = nil
            realtimeTranscriber.onError = nil
            audioRecorder.onAudioChunk = nil
            
            audioRecorder.stopStreamingRecording()
            realtimeTranscriber.disconnect()
            stateManager.isFastMode = false
            stateManager.clearPartialTranscript()
        } else {
            audioRecorder.cancelRecording()
        }
        stateManager.cancelRecording()
    }
    
    // MARK: - Transcription Flow
    
    private func transcribe(audioURL: URL) {
        print("[WhisprFlow] transcribe() called for: \(audioURL.lastPathComponent)")
        logToFile("[AppDelegate] Starting transcription for: \(audioURL.lastPathComponent)")
        
        Task {
            do {
                // Step 1: Compress audio to M4A for faster upload
                logToFile("[AppDelegate] Compressing audio to M4A...")
                let compressedURL: URL
                do {
                    compressedURL = try await audioRecorder.compressToM4A(wavURL: audioURL)
                    logToFile("[AppDelegate] Compression successful: \(compressedURL.lastPathComponent)")
                } catch {
                    // If compression fails, use original WAV
                    logToFile("[AppDelegate] Compression failed, using original WAV: \(error.localizedDescription)")
                    compressedURL = audioURL
                }
                
                // Step 2: Transcribe
                print("[WhisprFlow] Calling transcription API...")
                logToFile("[AppDelegate] Calling transcription API...")
                let text = try await transcriptionManager.transcribe(audioURL: compressedURL)
                print("[WhisprFlow] Transcription SUCCESS: \"\(text.prefix(50))...\"")
                logToFile("[AppDelegate] Transcription SUCCESS: \(text.count) characters")
                
                // Cleanup compressed file
                try? FileManager.default.removeItem(at: compressedURL)
                
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
                }
            } catch {
                print("[WhisprFlow] Transcription UNEXPECTED ERROR: \(error.localizedDescription)")
                logToFile("[AppDelegate] Transcription UNEXPECTED ERROR: \(error.localizedDescription)")
                await MainActor.run {
                    stateManager.transcriptionFailed(error: .transcriptionFailed(error.localizedDescription))
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
            window.title = "WhisprFlow Settings"
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
            window.title = "WhisprFlow"
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
