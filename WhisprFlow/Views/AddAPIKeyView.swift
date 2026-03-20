import SwiftUI
import AppKit

/// Friendly prompt shown when trial ends, asking user to add their own OpenAI API key
struct AddAPIKeyView: View {
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var isValidating = false
    @State private var errorMessage: String?

    var onKeyAdded: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Image("WhisprIcon")
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Thanks for trying Whispr!")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text("You've used your free transcriptions")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.textSecondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()
                .background(Design.Colors.border)

            // Content
            VStack(alignment: .leading, spacing: 20) {
                // Info text
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add your OpenAI API key to continue")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Whispr is free to use with your own key. Getting an API key takes less than a minute.")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Get API Key link
                Button(action: openAPIKeyPage) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                        Text("How to get an API key")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Design.Colors.accent)
                }
                .buttonStyle(.plain)

                // API Key input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your API Key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Design.Colors.textSecondary)

                    HStack {
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
                                .font(.system(size: 12))
                                .foregroundStyle(Design.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Design.Colors.surfaceSecondary)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(errorMessage != nil ? Color.red.opacity(0.5) : Design.Colors.border, lineWidth: 1)
                    )

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }

                    Text("Your key is stored locally and never shared.")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.textTertiary)
                }

                // Save button
                Button(action: saveKey) {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        }
                        Text(isValidating ? "Validating..." : "Save API Key")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(apiKey.isEmpty ? Design.Colors.textTertiary : Design.Colors.accent)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(apiKey.isEmpty || isValidating)
            }
            .padding(24)

            Spacer()

            // Footer
            VStack(spacing: 8) {
                Divider()
                    .background(Design.Colors.border)

                HStack {
                    Text("Made with ♥ by")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.textTertiary)

                    Button(action: openDeveloperSite) {
                        Text("Prince Jain")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Design.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 400, height: 520)
        .background(Design.Colors.background)
    }

    private func openAPIKeyPage() {
        if let url = URL(string: "https://platform.openai.com/api-keys") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openDeveloperSite() {
        if let url = URL(string: "https://princejain.me") {
            NSWorkspace.shared.open(url)
        }
    }

    private func saveKey() {
        guard !apiKey.isEmpty else { return }

        // Basic validation
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedKey.hasPrefix("sk-") {
            errorMessage = "API key should start with 'sk-'"
            return
        }

        if trimmedKey.count < 20 {
            errorMessage = "API key seems too short"
            return
        }

        errorMessage = nil
        isValidating = true

        // Save the key
        if KeychainHelper.saveAPIKey(trimmedKey) {
            logToFile("[AddAPIKeyView] API key saved successfully")
            isValidating = false
            onKeyAdded?()
        } else {
            errorMessage = "Failed to save API key"
            isValidating = false
        }
    }
}

// MARK: - Window Controller

class AddAPIKeyWindowController: NSWindowController {
    private var onKeyAdded: (() -> Void)?

    convenience init(onKeyAdded: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)
        self.onKeyAdded = onKeyAdded

        window.title = "Add API Key"
        window.center()
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: AddAPIKeyView(
            onKeyAdded: { [weak self] in
                self?.window?.close()
                onKeyAdded()
            },
            onDismiss: { [weak self] in
                self?.window?.close()
            }
        ))

        window.contentView = hostingView
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Preview

#Preview {
    AddAPIKeyView()
}
