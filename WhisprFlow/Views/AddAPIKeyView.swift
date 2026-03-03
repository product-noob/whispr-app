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
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(hex: "8B5CF6"))
                
                Text("Thanks for trying Whispr!")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: "1F2937"))
                
                Text("You've used your free transcriptions")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "6B7280"))
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            
            Divider()
                .background(Color(hex: "E5E5E5"))
            
            // Content
            VStack(alignment: .leading, spacing: 20) {
                // Info text
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add your OpenAI API key to continue")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "1F2937"))
                    
                    Text("Whispr is free to use with your own key. Getting an API key takes less than a minute.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "6B7280"))
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
                    .foregroundStyle(Color(hex: "8B5CF6"))
                }
                .buttonStyle(.plain)
                
                // API Key input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your API Key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "6B7280"))
                    
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
                                .foregroundStyle(Color(hex: "9CA3AF"))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color(hex: "F9FAFB"))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(errorMessage != nil ? Color.red.opacity(0.5) : Color(hex: "E5E5E5"), lineWidth: 1)
                    )
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    
                    Text("Your key is stored locally and never shared.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "9CA3AF"))
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
                    .background(apiKey.isEmpty ? Color(hex: "9CA3AF") : Color(hex: "8B5CF6"))
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
                    .background(Color(hex: "E5E5E5"))
                
                HStack {
                    Text("Made with ♥ by")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                    
                    Button(action: openDeveloperSite) {
                        Text("Prince Jain")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "8B5CF6"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 400, height: 520)
        .background(Color.white)
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
