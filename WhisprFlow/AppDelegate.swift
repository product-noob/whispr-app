import AppKit
import SwiftUI
import os.log
#if canImport(Sparkle)
import Sparkle
#endif

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
    private var historyWindowController: NSWindowController?
    private var addAPIKeyWindowController: AddAPIKeyWindowController?
    private var onboardingController: OnboardingWindowController?
    private var accessibilityPollTimer: Timer?

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    #endif

    // MARK: - Menu Bar
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logToFile("=== WhisprFlow Starting ===")
        NSApp.setActivationPolicy(.accessory)

        if !ConfigStore.shared.config.hasCompletedOnboarding {
            showOnboarding()
            return
        }

        completeSetup()
    }

    private func showOnboarding() {
        onboardingController = OnboardingWindowController()
        onboardingController?.show { [weak self] in
            self?.onboardingController = nil
            self?.completeSetup()
        }
    }

    private func completeSetup() {
        setupApp()
        setupHotkeys()
        setupMenuBar()
        showPillWindow()
        observeScreenChanges()
        checkInitialPermissions()
        observeModelChanges()

        #if canImport(Sparkle)
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif

        logToFile("=== WhisprFlow Started ===")
    }

    private func observeModelChanges() {
        NotificationCenter.default.addObserver(
            forName: .whisprModelChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                let model = TranscriptionModel(rawValue: ConfigStore.shared.config.selectedModel) ?? .openAI
                logToFile("[AppDelegate] Model changed to: \(model.displayName), reloading...")
                do {
                    try await self.transcriptionManager.setModel(model)
                    logToFile("[AppDelegate] Model reloaded: \(model.displayName)")
                } catch {
                    logToFile("[AppDelegate] Model reload failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    
    // MARK: - Setup
    
    private func setupApp() {
        // Preload selected transcription model in background
        Task {
            let model = TranscriptionModel(rawValue: ConfigStore.shared.config.selectedModel) ?? .openAI
            do {
                try await transcriptionManager.setModel(model)
                logToFile("[AppDelegate] Model preloaded: \(model.displayName)")
            } catch {
                logToFile("[AppDelegate] Model preload failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupMenuBar() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            if let iconImage = NSImage(named: "MenuBarIcon") {
                iconImage.size = NSSize(width: 18, height: 18)
                iconImage.isTemplate = false
                button.image = iconImage
            } else if let fallback = NSImage(named: "WhisprIcon") {
                fallback.size = NSSize(width: 18, height: 18)
                fallback.isTemplate = false
                button.image = fallback
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
            if let iconImage = NSImage(named: "MenuBarIcon") {
                iconImage.size = NSSize(width: 18, height: 18)
                iconImage.isTemplate = false
                button.image = iconImage
            } else if let fallback = NSImage(named: "WhisprIcon") {
                fallback.size = NSSize(width: 18, height: 18)
                fallback.isTemplate = false
                button.image = fallback
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

        hotkeyManager.onHandsFreeStart = { [weak self] in
            logToFile("Hands-free mode START")
            self?.startRecording()
        }

        hotkeyManager.onHandsFreeStop = { [weak self] in
            logToFile("Hands-free mode STOP")
            self?.stopRecording()
        }

        hotkeyManager.onCancel = { [weak self] in
            logToFile("Hotkey CANCEL detected")
            self?.cancelRecording()
        }

        let started = hotkeyManager.start()
        logToFile("Hotkey manager started: \(started)")
        if !started {
            logToFile("ERROR: Failed to start hotkey manager - accessibility permission may be needed")
        }
    }
    
    private func showPillWindow() {
        let callbacks = PillCallbacks(
            hotkeyManager: hotkeyManager,
            audioRecorder: audioRecorder,
            onStartRecording: { [weak self] in self?.startRecording() },
            onStopRecording: { [weak self] in self?.stopRecording() },
            onCancelRecording: { [weak self] in self?.cancelRecording() },
            onCancelTranscription: { [weak self] in self?.cancelTranscription() },
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
            // Trigger the system prompt (may be suppressed on macOS 14+ if previously removed)
            _ = hotkeyManager.checkAccessibilityPermission()
            // Also open System Settings directly — the system prompt alone is unreliable
            // after the user has previously removed the app from Accessibility
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            // Poll until granted (no timeout — keeps checking every 2s)
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
    
    /// Poll for accessibility permission and restart hotkey manager when granted.
    /// Polls indefinitely every 2 seconds — the user may take a while to find and toggle the setting.
    private func startAccessibilityPermissionPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.hotkeyManager.hasAccessibilityPermission {
                timer.invalidate()
                self.accessibilityPollTimer = nil
                logToFile("Accessibility permission now granted, restarting hotkey manager...")
                let started = self.hotkeyManager.start()
                logToFile("Hotkey manager restarted: \(started)")
            }
        }
    }
    
    /// Schedule automatic recovery from error state after a delay
    /// Uses a shorter delay for non-critical errors like empty transcription
    private func scheduleErrorRecovery(quick: Bool = false) {
        let delay: Double = quick ? 0.8 : 4.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
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
    
    /// Bundle ID of the app that was active when recording started (for context-aware post-processing)
    private var activeAppBundleID: String?

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
        
        // Check if we can transcribe (local model, trial active, OR user has own key)
        guard TrialTracker.shared.canTranscribe else {
            print("[WhisprFlow] ERROR: Trial ended and no API key configured")
            stateManager.setError(.noAPIKey)
            scheduleErrorRecovery()
            showAddAPIKeyPrompt()
            return
        }
        
        // Capture the frontmost app before recording starts
        activeAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

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

                // F6: Minimum duration guard — skip transcription for accidental taps (<0.3s)
                let duration = audioRecorder.wavDuration(at: audioURL)
                if duration < 0.15 {
                    logToFile("[AppDelegate] Recording too short (\(String(format: "%.2f", duration))s), discarding")
                    try? FileManager.default.removeItem(at: audioURL)
                    await MainActor.run { stateManager.reset() }
                    return
                }

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

    private func cancelTranscription() {
        guard stateManager.canCancelTranscription else { return }
        logToFile("[AppDelegate] Cancelling transcription")
        transcriptionManager.cancel()
        if let url = stateManager.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        stateManager.cancelTranscription()
    }
    
    // MARK: - Transcription Flow
    
    private func transcribe(audioURL: URL) {
        print("[WhisprFlow] transcribe() called for: \(audioURL.lastPathComponent)")
        logToFile("[AppDelegate] Starting transcription for: \(audioURL.lastPathComponent)")
        
        let capturedBundleID = activeAppBundleID

        Task {
            do {
                // Step 1: Silence trimming (F5) — remove leading/trailing silence
                var processedURL = audioURL
                if let trimmedURL = audioRecorder.trimSilence(wavURL: processedURL) {
                    processedURL = trimmedURL
                } else {
                    // Entire file was silence — no speech detected
                    logToFile("[AppDelegate] No speech detected (all silence), skipping transcription")
                    try? FileManager.default.removeItem(at: audioURL)
                    await MainActor.run {
                        stateManager.reset()
                    }
                    return
                }

                // Step 2: Audio normalization (F7) — boost quiet recordings
                processedURL = audioRecorder.normalizeAudio(wavURL: processedURL)

                // Step 2.5: Pad short audio to meet OpenAI's 1-second minimum
                processedURL = audioRecorder.padToMinimumDuration(wavURL: processedURL)

                // Step 3: Optionally compress audio (skip for local models and small files)
                let selectedModel = TranscriptionModel(rawValue: ConfigStore.shared.config.selectedModel) ?? .openAI
                let finalURL: URL
                if selectedModel == .openAI && audioRecorder.shouldCompress(fileURL: processedURL) {
                    logToFile("[AppDelegate] Compressing audio to M4A...")
                    do {
                        finalURL = try await audioRecorder.compressToM4A(wavURL: processedURL)
                        logToFile("[AppDelegate] Compression successful: \(finalURL.lastPathComponent)")
                    } catch {
                        logToFile("[AppDelegate] Compression failed, using original WAV: \(error.localizedDescription)")
                        finalURL = processedURL
                    }
                } else {
                    logToFile("[AppDelegate] Skipping compression (local model or small file)")
                    finalURL = processedURL
                }

                // Step 4: Transcribe
                print("[WhisprFlow] Calling transcription...")
                logToFile("[AppDelegate] Calling transcription...")
                let rawText = try await transcriptionManager.transcribe(audioURL: finalURL)

                // Filter out non-English hallucinations (Parakeet sometimes outputs Cyrillic/CJK)
                if TextPostProcessor.appearsNonEnglish(rawText) {
                    logToFile("[AppDelegate] Non-English output detected, discarding: \(rawText.prefix(50))")
                    try? FileManager.default.removeItem(at: finalURL)
                    await MainActor.run {
                        stateManager.reset()
                    }
                    return
                }

                let text = TextPostProcessor.process(rawText, config: ConfigStore.shared.config, activeAppBundleID: capturedBundleID)
                print("[WhisprFlow] Transcription SUCCESS: \"\(text.prefix(50))...\"")
                logToFile("[AppDelegate] Transcription SUCCESS: \(text.count) characters (raw: \(rawText.count))")

                // Cleanup audio file
                try? FileManager.default.removeItem(at: finalURL)

                await MainActor.run {
                    stateManager.transcriptionSucceeded(text: text)

                    // Save to history
                    historyStore.addEntry(text)

                    insertText(text)
                }
            } catch let error as TranscriptionError {
                print("[WhisprFlow] Transcription ERROR: \(error.localizedDescription)")
                logToFile("[AppDelegate] Transcription ERROR (TranscriptionError): \(error) — localizedDescription: \(error.localizedDescription)")
                if case .emptyTranscription = error {
                    logToFile("[AppDelegate] >>> emptyTranscription detected, calling reset() directly")
                    await MainActor.run { stateManager.reset() }
                    return
                }
                await MainActor.run {
                    switch error {
                    case .noAPIKey:
                        logToFile("[AppDelegate] >>> Mapped to: noAPIKey")
                        stateManager.transcriptionFailed(error: .noAPIKey)
                    case .trialEnded:
                        logToFile("[AppDelegate] >>> Mapped to: trialEnded → noAPIKey")
                        stateManager.transcriptionFailed(error: .noAPIKey)
                        showAddAPIKeyPrompt()
                    case .invalidAPIKey:
                        logToFile("[AppDelegate] >>> Mapped to: invalidAPIKey")
                        stateManager.transcriptionFailed(error: .invalidAPIKey)
                    case .timeout:
                        logToFile("[AppDelegate] >>> Mapped to: timeout")
                        stateManager.transcriptionFailed(error: .transcriptionTimeout)
                    case .networkError(let msg):
                        logToFile("[AppDelegate] >>> Mapped to: networkError(\(msg))")
                        stateManager.transcriptionFailed(error: .networkError(msg))
                    default:
                        logToFile("[AppDelegate] >>> Mapped to DEFAULT: transcriptionFailed(\(error.localizedDescription))")
                        stateManager.transcriptionFailed(error: .transcriptionFailed(error.localizedDescription))
                    }
                    scheduleErrorRecovery()
                }
            } catch {
                print("[WhisprFlow] Transcription UNEXPECTED ERROR: \(error.localizedDescription)")
                logToFile("[AppDelegate] Transcription UNEXPECTED ERROR (not TranscriptionError): type=\(type(of: error)), desc=\(error.localizedDescription)")
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
        if historyWindowController == nil {
            let historyView = HistoryView(
                historyStore: historyStore,
                hotkeyManager: hotkeyManager,
                outputDispatcher: outputDispatcher,
                onStartRecording: { [weak self] in
                    self?.historyWindowController?.window?.close()
                    self?.startRecording()
                },
                onClose: { [weak self] in
                    self?.historyWindowController?.window?.close()
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
            window.collectionBehavior.insert(.fullScreenPrimary)

            let controller = NSWindowController(window: window)
            historyWindowController = controller
        }

        historyWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
