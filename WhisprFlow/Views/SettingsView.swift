import SwiftUI

/// Full settings view for WhisprFlow configuration
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var selectedHotkey: HotkeyManager.HotkeyType = .fnKey
    @State private var selectedOutputMode: OutputDispatcher.OutputMode = .paste
    @State private var hasAccessibilityPermission = false
    @State private var hasMicrophonePermission = false
    @State private var showSaveConfirmation = false
    @State private var launchAtLogin = false
    
    let hotkeyManager: HotkeyManager
    let outputDispatcher: OutputDispatcher
    var onSave: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    apiKeySection
                    hotkeySection
                    outputSection
                    generalSection
                    permissionsSection
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 480, height: 560)
        .background(Design.Colors.background)
        .onAppear {
            loadSettings()
        }
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
                        .stroke(apiKey.isEmpty ? Design.Colors.error.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                
                Text("Your API key is stored securely in the macOS Keychain")
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
    
    // MARK: - General Section
    
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("General", icon: "gearshape")
            
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "power")
                        .foregroundStyle(Design.Colors.textSecondary)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.system(size: 13))
                            .foregroundStyle(Design.Colors.textPrimary)
                        
                        Text("Start Whispr automatically when you log in")
                            .font(.system(size: 11))
                            .foregroundStyle(Design.Colors.textTertiary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, newValue in
                            LaunchAtLogin.isEnabled = newValue
                        }
                }
                .padding(10)
                .background(Design.Colors.background)
                .cornerRadius(8)
            }
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
                Button("Enable") {
                    action()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Design.Colors.accent)
            }
        }
        .padding(10)
        .background(Design.Colors.background)
        .cornerRadius(8)
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
            .disabled(apiKey.isEmpty)
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
    
    private func loadSettings() {
        apiKey = KeychainHelper.getAPIKey() ?? ""
        selectedHotkey = hotkeyManager.currentHotkey
        selectedOutputMode = outputDispatcher.outputMode
        hasAccessibilityPermission = hotkeyManager.hasAccessibilityPermission
        hasMicrophonePermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        launchAtLogin = LaunchAtLogin.isEnabled
    }
    
    private func saveSettings() {
        // Save API key
        if !apiKey.isEmpty {
            KeychainHelper.saveAPIKey(apiKey)
        }
        
        // Save hotkey
        hotkeyManager.setHotkey(selectedHotkey)
        
        // Save output mode
        outputDispatcher.outputMode = selectedOutputMode
        
        // Show confirmation
        showSaveConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaveConfirmation = false
        }
        
        onSave?()
    }
    
    private func resetToDefaults() {
        selectedHotkey = .fnKey
        selectedOutputMode = .paste
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

import AVFoundation

#Preview {
    SettingsView(
        hotkeyManager: HotkeyManager(),
        outputDispatcher: OutputDispatcher()
    )
}
