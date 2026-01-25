import SwiftUI

/// The main floating pill UI - small dark translucent pill that expands on hover
struct PillView: View {
    @Bindable var stateManager: AppStateManager
    let hotkeyManager: HotkeyManager
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    
    @State private var isHovering = false
    @State private var showToast = false
    @State private var toastMessage = ""
    
    // Get the current hotkey display name from the manager
    private var hotkeyName: String {
        switch hotkeyManager.currentHotkey {
        case .fnKey: return "fn"
        case .controlSpace: return "⌃ Space"
        case .optionSpace: return "⌥ Space"
        case .commandShiftSpace: return "⌘⇧ Space"
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Spacer() // Push content to bottom
            
            // Toast message
            if showToast {
                toastView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Main pill
            mainPill
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: stateManager.state)
        .animation(Design.Animation.stateTransition, value: showToast)
    }
    
    private var mainPill: some View {
        Group {
            if isHovering || !stateManager.state.isIdle {
                expandedPill
            } else {
                collapsedPill
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Settings") {
                onOpenHistory?()  // Opens the dashboard which contains all tabs
            }
            Divider()
            Button("Quit WhisprFlow") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    // MARK: - Collapsed Pill (Small dark translucent)
    
    private var collapsedPill: some View {
        Button(action: handlePillTap) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.6))
                .frame(width: 48, height: 16)
        }
        .buttonStyle(.plain)
        .help("Click or hold \(hotkeyName) to start dictating")
    }
    
    // MARK: - Expanded Pill (Full UI)
    
    private var expandedPill: some View {
        HStack(spacing: 12) {
            pillContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }
    
    @ViewBuilder
    private var pillContent: some View {
        switch stateManager.state {
        case .idle:
            idleContent
        case .recording:
            recordingContent
        case .transcribing:
            transcribingContent
        case .error(let error):
            errorContent(error: error)
        }
    }
    
    // MARK: - Idle State
    
    private var idleContent: some View {
        Button(action: handlePillTap) {
            HStack(spacing: 8) {
                Text("Click or hold")
                    .foregroundStyle(.white.opacity(0.7))
                
                Text(hotkeyName)
                    .foregroundStyle(Color(hex: "E879F9")) // Pink/purple accent
                    .fontWeight(.medium)
                
                Text("to start dictating")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 13))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Recording State
    
    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Animated recording indicator
                HStack(spacing: 3) {
                    ForEach(0..<5) { i in
                        RecordingBar(index: i)
                    }
                }
                .frame(width: 30)
                
                // Show "Recording..." or partial transcript
                if stateManager.isFastMode && !stateManager.partialTranscript.isEmpty {
                    Text(stateManager.partialTranscript)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .truncationMode(.head)
                } else {
                    Text(stateManager.isFastMode ? "Listening..." : "Recording...")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                Spacer()
                
                // Stop button
                Button(action: handleStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                // Cancel button
                Button(action: handleCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            
            // Fast mode indicator
            if stateManager.isFastMode {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                    Text("Fast mode")
                        .font(.system(size: 9))
                }
                .foregroundStyle(Color(hex: "F59E0B"))
            }
        }
    }
    
    // MARK: - Transcribing State
    
    private var transcribingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            
            Text("Transcribing...")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
    
    // MARK: - Error State
    
    private func errorContent(error: RecordingError) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
            
            Text(error.errorDescription ?? "Error")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            
            Spacer()
            
            if error.isRetryable {
                Button(action: handleRetry) {
                    Text("Retry")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            Button(action: handleDiscard) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Toast
    
    private var toastView: some View {
        Text(toastMessage)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
    }
    
    func showToast(_ message: String, duration: TimeInterval = 2) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            showToast = false
        }
    }
    
    // MARK: - Actions
    
    private func handlePillTap() {
        guard stateManager.canStartRecording else { return }
        onStartRecording?()
    }
    
    private func handleStop() {
        guard stateManager.canStopRecording else { return }
        onStopRecording?()
    }
    
    private func handleCancel() {
        onCancelRecording?()
    }
    
    private func handleRetry() {
        onRetry?()
    }
    
    private func handleDiscard() {
        onDiscard?()
    }
}

// MARK: - Recording Animation Bar

struct RecordingBar: View {
    let index: Int
    @State private var animating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(hex: "34C759")) // Green
            .frame(width: 3, height: animating ? CGFloat.random(in: 8...20) : 6)
            .animation(
                .easeInOut(duration: 0.3)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.1),
                value: animating
            )
            .onAppear {
                animating = true
            }
    }
}

// MARK: - Preview

#Preview("Collapsed") {
    let manager = AppStateManager()
    return PillView(stateManager: manager, hotkeyManager: HotkeyManager())
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Expanded Idle") {
    let manager = AppStateManager()
    return PillView(stateManager: manager, hotkeyManager: HotkeyManager())
        .padding(40)
        .background(Color.gray.opacity(0.3))
        .onAppear {
            // Simulate hover
        }
}

#Preview("Recording") {
    let manager = AppStateManager()
    manager.startRecording()
    return PillView(stateManager: manager, hotkeyManager: HotkeyManager())
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
