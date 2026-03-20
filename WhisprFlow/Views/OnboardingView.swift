import AVFoundation
import ApplicationServices
import SwiftUI

// MARK: - Onboarding Window Controller

final class OnboardingWindowController {
    private var window: NSWindow?

    func show(onComplete: @escaping () -> Void) {
        let view = OnboardingView(onComplete: { [weak self] in
            self?.window?.close()
            self?.window = nil
            onComplete()
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Whispr"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var selectedModel: TranscriptionModel = .parakeetV3
    @State private var selectedHotkey: HotkeyManager.HotkeyType = .fnKey

    // Permission states
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var pendingPermissions: Set<String> = []

    // API key (for OpenAI selection)
    @State private var apiKey = ""

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: modelStep
                case 2: permissionsStep
                case 3: hotkeyStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Divider()

            // Bottom bar
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep ? Design.Colors.accent : Design.Colors.textTertiary)
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.2)) { currentStep -= 1 }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Design.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    primaryButton
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Design.Colors.surface)
        }
        .frame(width: 600, height: 520)
        .background(Design.Colors.background)
    }

    // MARK: - Primary Button

    @ViewBuilder
    private var primaryButton: some View {
        switch currentStep {
        case 0:
            accentButton("Get Started") {
                withAnimation(.easeInOut(duration: 0.2)) { currentStep = 1 }
            }
        case 1:
            accentButton(selectedModel.isLocal ? "Download & Continue" : "Continue") {
                if selectedModel.isLocal {
                    // Start download in background, advance immediately
                    Task {
                        try? await ModelManager.shared.downloadModel(selectedModel)
                    }
                }
                if selectedModel == .openAI && !apiKey.isEmpty {
                    _ = KeychainHelper.saveAPIKey(apiKey)
                }
                withAnimation(.easeInOut(duration: 0.2)) { currentStep = 2 }
            }
        case 2:
            accentButton("Continue") {
                withAnimation(.easeInOut(duration: 0.2)) { currentStep = 3 }
            }
        case 3:
            accentButton("Finish Setup") {
                finishOnboarding()
            }
        default:
            EmptyView()
        }
    }

    private func accentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Design.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            if let icon = NSImage(named: NSImage.Name("AppIcon")) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            VStack(spacing: 8) {
                Text("Welcome to Whispr")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text("Voice-to-text dictation for macOS.\nPress a hotkey, speak, and your words appear as text.")
                    .font(.system(size: 15))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Step 1: Model Selection

    private var modelStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Choose your transcription model")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text("Pick a model to get started. You can change this later in Settings.")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(TranscriptionModel.allCases) { model in
                        modelCard(model)
                    }
                }
                .padding(.horizontal, 32)
            }

            if selectedModel == .openAI {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenAI API Key")
                        .font(.system(size: 12))
                        .foregroundStyle(Design.Colors.textTertiary)
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(Design.Colors.surface)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Design.Colors.textTertiary.opacity(0.3), lineWidth: 1)
                        )
                }
                .frame(width: 320)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func modelCard(_ model: TranscriptionModel) -> some View {
        let isSelected = selectedModel == model
        return Button { selectedModel = model } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(isSelected ? Design.Colors.accent : Color.clear)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? Design.Colors.accent : Design.Colors.textTertiary, lineWidth: 1.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 14, weight: .medium))
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

                        if model.downloadSizeMB > 0 {
                            Text("~\(model.downloadSizeMB) MB")
                                .font(.system(size: 11))
                                .foregroundStyle(Design.Colors.textTertiary)
                        }
                    }

                    Text(model.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Design.Colors.textSecondary)
                }

                Spacer()
            }
            .padding(12)
            .background(Design.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Design.Colors.accent : Design.Colors.textTertiary.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("System Permissions")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text("Whispr needs microphone access to record and accessibility permission for global hotkeys and auto-paste.")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                permissionRow(
                    icon: "mic.fill",
                    name: "Microphone",
                    description: "Record audio for dictation",
                    granted: micGranted,
                    pending: pendingPermissions.contains("mic"),
                    action: {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                        grantAfterDelay("mic") { micGranted = true }
                    }
                )

                Divider()

                permissionRow(
                    icon: "hand.raised.fill",
                    name: "Accessibility",
                    description: "Global hotkeys and paste simulation",
                    granted: accessibilityGranted,
                    pending: pendingPermissions.contains("accessibility"),
                    action: {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                        grantAfterDelay("accessibility") { accessibilityGranted = true }
                    }
                )
            }
            .background(Design.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Design.Colors.textTertiary.opacity(0.2), lineWidth: 1)
            )
            .frame(width: 440)

            Text("You can also grant these later in System Settings.")
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { refreshPermissions() }
    }

    private func permissionRow(icon: String, name: String, description: String, granted: Bool, pending: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Design.Colors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.textSecondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.success)
                    .transition(.scale.combined(with: .opacity))
            } else if pending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Design.Colors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Design.Colors.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.25), value: granted)
    }

    private func grantAfterDelay(_ key: String, grant: @escaping () -> Void) {
        pendingPermissions.insert(key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                pendingPermissions.remove(key)
                grant()
            }
        }
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
    }

    // MARK: - Step 3: Hotkey

    private var hotkeyStep: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Choose your hotkey")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text("Press and hold to record, release to transcribe.")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.textSecondary)
            }

            VStack(spacing: 8) {
                ForEach(HotkeyManager.HotkeyType.allCases, id: \.self) { type in
                    hotkeyOption(type)
                }
            }
            .frame(width: 320)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func hotkeyOption(_ type: HotkeyManager.HotkeyType) -> some View {
        let isSelected = selectedHotkey == type
        return Button { selectedHotkey = type } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Design.Colors.accent : Design.Colors.textTertiary)

                Text(type.displayName)
                    .font(.system(size: 14))
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
            .background(isSelected ? Design.Colors.accent.opacity(0.1) : Design.Colors.surface)
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

    // MARK: - Finish

    private func finishOnboarding() {
        ConfigStore.shared.update {
            $0.hasCompletedOnboarding = true
            $0.selectedModel = selectedModel.rawValue
            $0.hotkeyType = selectedHotkey.rawValue
        }
        onComplete()
    }
}
