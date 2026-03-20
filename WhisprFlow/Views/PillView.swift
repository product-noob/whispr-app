import SwiftUI

/// The main floating pill UI — compact, state-driven, with amplitude-responsive waveform
struct PillView: View {
    @Bindable var stateManager: AppStateManager
    let hotkeyManager: HotkeyManager
    var audioRecorder: AudioRecorder?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onCancelTranscription: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?

    @State private var isHovering = false
    @State private var hoverExitTask: Task<Void, Never>?
    @State private var audioAmplitude: CGFloat = 0
    @State private var amplitudeTimer: Timer?

    private var hotkeyName: String {
        switch hotkeyManager.currentHotkey {
        case .fnKey: return "fn"
        case .controlSpace: return "⌃ Space"
        case .optionSpace: return "⌥ Space"
        case .commandShiftSpace: return "⌘⇧ Space"
        }
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            pillContent
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contextMenu {
            Button("Dashboard") { onOpenHistory?() }
            Button("Settings") { onOpenSettings?() }
            Divider()
            Button("Quit Whispr") { NSApplication.shared.terminate(nil) }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: stateManager.state)
        .animation(.easeInOut(duration: 0.35), value: isHovering)
    }

    @ViewBuilder
    private var pillContent: some View {
        switch stateManager.state {
        case .idle:
            idlePill
        case .recording:
            recordingPill
        case .transcribing:
            transcribingPill
        case .error(let error):
            errorPill(error: error)
        }
    }

    // MARK: - Idle

    private func scheduleHoverExit() {
        hoverExitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            isHovering = false
        }
    }

    private var idlePill: some View {
        // Collapsed pill bar (always anchored)
        Button(action: { onStartRecording?() }) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.35))
                .frame(width: 40, height: 8)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoverExitTask?.cancel()
                isHovering = true
            } else {
                scheduleHoverExit()
            }
        }
        .overlay(alignment: .top) {
            // Floating hint label above the pill
            if isHovering {
                HStack(spacing: 4) {
                    Text("Click or hold")
                        .foregroundStyle(.white.opacity(0.7))
                    Text(hotkeyName)
                        .foregroundStyle(Color(hex: "E879F9"))
                        .fontWeight(.medium)
                    Text("to start dictating")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .font(.system(size: 13))
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.85))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
                .fixedSize()
                .offset(y: -42)
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
    }

    // MARK: - Recording (compact dot-animation pill)

    private var recordingPill: some View {
        HStack(spacing: 10) {
            // Cancel (X) on left — gray circle
            Button(action: { onCancelRecording?() }) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

            // Animated dots in center
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    RecordingDot(index: i, amplitude: audioAmplitude)
                }
            }

            // Stop button on right — pink/red rounded rect
            Button(action: { onStopRecording?() }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "E05A6A").opacity(0.35))
                        .frame(width: 28, height: 28)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "E05A6A"))
                        .frame(width: 11, height: 11)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(Color.black.opacity(0.85))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
        .onAppear { startAmplitudePolling() }
        .onDisappear { stopAmplitudePolling() }
    }

    // MARK: - Transcribing

    private var transcribingPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
                .tint(Design.Colors.accent)

            Text("Transcribing")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Button(action: { onCancelTranscription?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.7))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Design.Colors.accent.opacity(0.4), lineWidth: 1.5))
    }

    // MARK: - Error

    private func errorPill(error: RecordingError) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Design.Colors.error)

            Text(error.shortMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)

            if error.isRetryable {
                Button(action: { onRetry?() }) {
                    Text("Retry")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Button(action: { onDiscard?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.7))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Design.Colors.error.opacity(0.5), lineWidth: 1.5))
    }

    // MARK: - Amplitude Polling

    private func startAmplitudePolling() {
        amplitudeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            audioAmplitude = CGFloat(audioRecorder?.currentPowerLevel ?? 0)
        }
    }

    private func stopAmplitudePolling() {
        amplitudeTimer?.invalidate()
        amplitudeTimer = nil
        audioAmplitude = 0
    }
}

// MARK: - Recording Dot (amplitude-responsive)

struct RecordingDot: View {
    let index: Int
    let amplitude: CGFloat

    // Stagger multipliers so dots pulse at different intensities
    private static let multipliers: [CGFloat] = [0.4, 0.6, 0.8, 1.0, 0.8, 0.6, 0.4]
    private static let minSize: CGFloat = 4.0
    private static let maxSize: CGFloat = 7.0

    var body: some View {
        let multiplier = Self.multipliers[index]
        let size = Self.minSize + amplitude * (Self.maxSize - Self.minSize) * multiplier
        let opacity = 0.4 + amplitude * 0.6 * multiplier

        Circle()
            .fill(.white.opacity(opacity))
            .frame(width: size, height: size)
            .animation(.easeOut(duration: 0.08), value: amplitude)
    }
}

// MARK: - RecordingError short message

extension RecordingError {
    var shortMessage: String {
        switch self {
        case .microphonePermissionDenied: return "No mic access"
        case .microphoneUnavailable: return "Mic unavailable"
        case .noAPIKey: return "No API key"
        case .invalidAPIKey: return "Bad API key"
        case .emptyTranscription: return "No speech detected"
        case .transcriptionTimeout: return "Timed out"
        case .recordingFailed: return "Recording failed"
        case .transcriptionFailed: return "Failed"
        case .networkError: return "Network error"
        }
    }
}

// MARK: - Preview

#Preview("Idle") {
    PillView(stateManager: AppStateManager(), hotkeyManager: HotkeyManager())
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Recording") {
    let m = AppStateManager()
    m.startRecording()
    return PillView(stateManager: m, hotkeyManager: HotkeyManager())
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
