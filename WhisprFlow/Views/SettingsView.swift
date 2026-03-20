import AVFoundation
import SwiftUI

/// Full settings view for WhisprFlow configuration
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var selectedHotkey: HotkeyManager.HotkeyType = .fnKey
    @State private var selectedOutputMode: OutputDispatcher.OutputMode = .paste
    @State private var selectedModel: TranscriptionModel = .openAI
    @State private var hasAccessibilityPermission = false
    @State private var hasMicrophonePermission = false
    @State private var showSaveConfirmation = false
    @State private var launchAtLogin = false
    @State private var doubleTapHandsFree = true
    @State private var fillerWordRemoval = true
    @State private var personalDictionary: [DictionaryEntry] = []

    let hotkeyManager: HotkeyManager
    let outputDispatcher: OutputDispatcher
    var onSave: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    modelSection
                    apiKeySection
                    hotkeySection
                    dictationSection
                    outputSection
                    postProcessingSection
                    generalSection
                    permissionsSection
                    updatesSection
                }
                .padding(24)
            }

            Divider()
            footer
        }
        .frame(width: 500, height: 680)
        .background(Design.Colors.background)
        .onAppear { loadSettings() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Whispr Settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text("Configure your voice dictation preferences")
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.textSecondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Design.Colors.surface)
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Transcription Model", icon: "cpu")

            VStack(spacing: 8) {
                ForEach(TranscriptionModel.allCases) { model in
                    modelOption(model)
                }

                Text("Local models run on-device — no internet or API key needed")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Design.Colors.surface)
        .cornerRadius(12)
    }

    private func modelOption(_ model: TranscriptionModel) -> some View {
        let isSelected = selectedModel == model
        let isAvailable = model == .openAI || ModelManager.shared.isModelAvailable(model)

        return Button { selectedModel = model } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Design.Colors.accent : Design.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 13))
                            .foregroundStyle(Design.Colors.textPrimary)

                        if model.isRecommended {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Design.Colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    Text(model.description)
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.textSecondary)
                }

                Spacer()

                if model.isLocal {
                    if isAvailable {
                        Text("Ready")
                            .font(.system(size: 11))
                            .foregroundStyle(Design.Colors.success)
                    } else {
                        Text("~\(model.downloadSizeMB) MB")
                            .font(.system(size: 11))
                            .foregroundStyle(Design.Colors.textTertiary)
                    }
                }
            }
            .padding(10)
            .background(isSelected ? Design.Colors.accent.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("OpenAI API Key", icon: "key.fill")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if showAPIKey {
                        TextField("sk-...", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                    }

                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Design.Colors.surface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedModel == .openAI && apiKey.isEmpty ? Design.Colors.error.opacity(0.5) : Color.clear, lineWidth: 1)
                )

                Text(selectedModel.isLocal ? "Only needed if you switch to OpenAI model" : "Required for OpenAI cloud transcription")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
            }
        }
        .padding(16)
        .background(Design.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Hotkey", icon: "command")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(HotkeyManager.HotkeyType.allCases, id: \.self) { type in
                    hotkeyOption(type)
                }

                Text("Press and hold the hotkey to record, release to transcribe")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Design.Colors.surface)
        .cornerRadius(12)
    }

    private func hotkeyOption(_ type: HotkeyManager.HotkeyType) -> some View {
        Button(action: { selectedHotkey = type }) {
            HStack {
                Image(systemName: selectedHotkey == type ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedHotkey == type ? Design.Colors.accent : Design.Colors.textTertiary)

                Text(type.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.textPrimary)

                Spacer()

                Text(hotkeySymbol(type))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Design.Colors.background)
                    .cornerRadius(4)
            }
            .padding(10)
            .background(selectedHotkey == type ? Design.Colors.accent.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func hotkeySymbol(_ type: HotkeyManager.HotkeyType) -> String {
        switch type {
        case .fnKey: return "fn"
        case .controlSpace: return "⌃ Space"
        case .optionSpace: return "⌥ Space"
        case .commandShiftSpace: return "⌘⇧ Space"
        }
    }

    // MARK: - Dictation Section

    private var dictationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Dictation", icon: "waveform")

            toggleRow(
                icon: "hand.tap",
                title: "Double-tap for hands-free mode",
                subtitle: "Double-tap hotkey to start recording, press any key to stop",
                isOn: $doubleTapHandsFree
            )
        }
        .padding(16)
        .background(Design.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Output Section

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Output Mode", icon: "doc.on.clipboard")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(OutputDispatcher.OutputMode.allCases, id: \.self) { mode in
                    outputOption(mode)
                }

                Text("Auto-paste inserts text directly; clipboard mode lets you paste manually")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Design.Colors.surface)
        .cornerRadius(12)
    }

    private func outputOption(_ mode: OutputDispatcher.OutputMode) -> some View {
        Button(action: { selectedOutputMode = mode }) {
            HStack {
                Image(systemName: selectedOutputMode == mode ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedOutputMode == mode ? Design.Colors.accent : Design.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text(mode == .paste ? "Simulates Cmd+V after copying" : "Copies text, you paste manually")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.textTertiary)
                }

                Spacer()
            }
            .padding(10)
            .background(selectedOutputMode == mode ? Design.Colors.accent.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Post-Processing Section

    private var postProcessingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Post-Processing", icon: "text.badge.checkmark")

            toggleRow(
                icon: "textformat.abc",
                title: "Remove filler words",
                subtitle: "Automatically removes \"uh\", \"um\", \"like,\" etc.",
                isOn: $fillerWordRemoval
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "book")
                        .foregroundStyle(Design.Colors.textSecondary)
                        .frame(width: 20)

                    Text("Personal Dictionary")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.textPrimary)

                    Spacer()

                    Button {
                        personalDictionary.append(DictionaryEntry(word: "", replacement: ""))
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Design.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }

                if !personalDictionary.isEmpty {
                    VStack(spacing: 6) {
                        ForEach($personalDictionary) { $entry in
                            HStack(spacing: 8) {
                                TextField("Word", text: $entry.word)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .padding(6)
                                    .background(Design.Colors.background)
                                    .cornerRadius(4)
                                    .frame(maxWidth: 140)

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Design.Colors.textTertiary)

                                TextField("Replacement", text: $entry.replacement)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .padding(6)
                                    .background(Design.Colors.background)
                                    .cornerRadius(4)
                                    .frame(maxWidth: 140)

                                Button {
                                    personalDictionary.removeAll { $0.id == entry.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(Design.Colors.error.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(8)
                    .background(Design.Colors.background)
                    .cornerRadius(8)
                }

                Text("Words will be fuzzy-matched and replaced in transcriptions")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            .padding(10)
            .background(Design.Colors.background)
            .cornerRadius(8)
        }
        .padding(16)
        .background(Design.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("General", icon: "gearshape")

            toggleRow(
                icon: "power",
                title: "Launch at Login",
                subtitle: "Start Whispr automatically when you log in",
                isOn: $launchAtLogin
            )
        }
        .padding(16)
        .background(Design.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Permissions", icon: "lock.shield")

            VStack(spacing: 8) {
                permissionRow(
                    "Microphone",
                    icon: "mic.fill",
                    granted: hasMicrophonePermission,
                    action: openMicrophoneSettings
                )

                permissionRow(
                    "Accessibility",
                    icon: "accessibility",
                    granted: hasAccessibilityPermission,
                    action: openAccessibilitySettings
                )
            }

            Text("Accessibility is required for global hotkeys and auto-paste")
                .font(.system(size: 11))
                .foregroundStyle(Design.Colors.textTertiary)
                .padding(.top, 4)
        }
        .padding(16)
        .background(Design.Colors.surface)
        .cornerRadius(12)
    }

    private func permissionRow(_ title: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(granted ? Design.Colors.success : Design.Colors.textTertiary)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.textPrimary)

            Spacer()

            if granted {
                Text("Granted")
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.success)
            } else {
                Button("Enable") { action() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Design.Colors.accent)
            }
        }
        .padding(10)
        .background(Design.Colors.background)
        .cornerRadius(8)
    }

    // MARK: - Updates Section

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Updates", icon: "arrow.triangle.2.circlepath")

            HStack {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Design.Colors.textSecondary)
                    .frame(width: 20)

                Text("Check for Updates")
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.textPrimary)

                Spacer()

                Button("Check Now") {
                    checkForUpdates()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Design.Colors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Design.Colors.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(10)
            .background(Design.Colors.background)
            .cornerRadius(8)
        }
        .padding(16)
        .background(Design.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Reset to Defaults") {
                resetToDefaults()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Design.Colors.textSecondary)

            Spacer()

            if showSaveConfirmation {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Saved")
                }
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.success)
                .transition(.opacity)
            }

            Button("Save") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(Design.Colors.accent)
        }
        .padding(20)
        .background(Design.Colors.surface)
        .animation(.easeInOut, value: showSaveConfirmation)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Design.Colors.accent)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Design.Colors.textPrimary)
        }
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Design.Colors.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(10)
        .background(Design.Colors.background)
        .cornerRadius(8)
    }

    private func loadSettings() {
        let config = ConfigStore.shared.config
        apiKey = KeychainHelper.getAPIKey() ?? ""
        selectedHotkey = hotkeyManager.currentHotkey
        selectedOutputMode = outputDispatcher.outputMode
        selectedModel = TranscriptionModel(rawValue: config.selectedModel) ?? .openAI
        hasAccessibilityPermission = hotkeyManager.hasAccessibilityPermission
        hasMicrophonePermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        launchAtLogin = config.launchAtLogin
        doubleTapHandsFree = config.doubleTapHandsFree
        fillerWordRemoval = config.fillerWordRemoval
        personalDictionary = config.personalDictionary
    }

    private func saveSettings() {
        // Save API key separately (sensitive data stays out of config)
        if !apiKey.isEmpty {
            _ = KeychainHelper.saveAPIKey(apiKey)
        }

        // Save hotkey
        hotkeyManager.setHotkey(selectedHotkey)

        // Save output mode
        outputDispatcher.outputMode = selectedOutputMode

        // Save launch at login
        LaunchAtLogin.isEnabled = launchAtLogin

        // Save config
        ConfigStore.shared.update {
            $0.selectedModel = selectedModel.rawValue
            $0.doubleTapHandsFree = doubleTapHandsFree
            $0.fillerWordRemoval = fillerWordRemoval
            $0.personalDictionary = personalDictionary
            $0.launchAtLogin = launchAtLogin
        }

        // Notify AppDelegate to reload model
        NotificationCenter.default.post(name: .whisprModelChanged, object: nil)

        showSaveConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaveConfirmation = false
        }

        onSave?()
    }

    private func resetToDefaults() {
        selectedHotkey = .fnKey
        selectedOutputMode = .paste
        selectedModel = .openAI
        doubleTapHandsFree = true
        fillerWordRemoval = true
        personalDictionary = []
    }

    private func checkForUpdates() {
        #if canImport(Sparkle)
        // Find the updater controller from AppDelegate
        if NSApp.delegate is AppDelegate {
            // Sparkle's check for updates is handled through the controller
            logToFile("[Settings] Check for updates requested")
        }
        #endif
        logToFile("[Settings] Check for updates — Sparkle not available")
    }

    private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    SettingsView(
        hotkeyManager: HotkeyManager(),
        outputDispatcher: OutputDispatcher()
    )
}
