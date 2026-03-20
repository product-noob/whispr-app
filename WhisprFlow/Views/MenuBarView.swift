import SwiftUI

/// Menu bar popover view - Minimalist control panel for Whispr
struct MenuBarView: View {
    @Bindable var stateManager: AppStateManager
    let hotkeyManager: HotkeyManager
    let outputDispatcher: OutputDispatcher
    var historyStore: HistoryStore?
    var onStartRecording: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?

    @State private var copiedLast = false

    private var hotkeySymbol: String {
        switch hotkeyManager.currentHotkey {
        case .fnKey: return "fn"
        case .controlSpace: return "⌃ Space"
        case .optionSpace: return "⌥ Space"
        case .commandShiftSpace: return "⌘⇧ Space"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .background(Design.Colors.border)

            VStack(spacing: 16) {
                // Hotkey hint
                hotkeyHint

                // Stats
                statsSection

                // Recent transcription
                if let lastEntry = historyStore?.lastEntry {
                    recentSection(lastEntry)
                }

                Spacer(minLength: 0)

                // Actions
                actionsSection
            }
            .padding(16)
        }
        .frame(width: 300, height: 380)
        .background(Design.Colors.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image("WhisprIcon")
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Whispr")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Design.Colors.textPrimary)
            }

            Spacer()

            // Trial badge (compact) or status badge
            if !KeychainHelper.hasAPIKey {
                trialBadge
            } else {
                statusBadge
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Design.Colors.fill)
        .cornerRadius(10)
    }

    private var trialBadge: some View {
        let remaining = TrialTracker.shared.transcriptionsRemaining
        let isLow = remaining <= 5

        return HStack(spacing: 4) {
            Image(systemName: "gift.fill")
                .font(.system(size: 9))

            Text("\(remaining) left")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(isLow ? Color.orange : Design.Colors.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isLow ? Color.orange.opacity(0.1) : Design.Colors.accent.opacity(0.1))
        .cornerRadius(10)
    }

    private var statusColor: Color {
        switch stateManager.state {
        case .idle: return Design.Colors.success
        case .recording: return Design.Colors.recording
        case .transcribing: return Color.orange
        case .error: return Design.Colors.error
        }
    }

    private var statusText: String {
        switch stateManager.state {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .error: return "Error"
        }
    }

    // MARK: - Hotkey Hint

    private var hotkeyHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.accent)

            Text("Hold")
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.textSecondary)

            Text(hotkeySymbol)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Design.Colors.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Design.Colors.fill)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Design.Colors.border, lineWidth: 1)
                )

            Text("to dictate")
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Design.Colors.surfaceSecondary)
        .cornerRadius(10)
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Design.Colors.textTertiary)
                .tracking(0.5)

            HStack(spacing: 10) {
                miniMetricCard(
                    value: "\(historyStore?.todayEntryCount ?? 0)",
                    label: "entries",
                    icon: "waveform",
                    color: Design.Colors.accent
                )

                miniMetricCard(
                    value: "\(historyStore?.todayWordCount ?? 0)",
                    label: "words",
                    icon: "text.word.spacing",
                    color: Design.Colors.success
                )

                miniMetricCard(
                    value: "\(historyStore?.totalEntries ?? 0)",
                    label: "total",
                    icon: "chart.bar.fill",
                    color: Color(hex: "F59E0B")
                )
            }
        }
    }

    private func miniMetricCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Design.Colors.textPrimary)

            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Design.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Design.Colors.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Design.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Recent Transcription

    private func recentSection(_ entry: TranscriptionEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Design.Colors.textTertiary)
                    .tracking(0.5)

                Spacer()

                Text(entry.formattedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Design.Colors.textTertiary)
            }

            HStack(alignment: .top, spacing: 10) {
                Text(entry.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(entry.text, forType: .string)
                    copiedLast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedLast = false
                    }
                }) {
                    Image(systemName: copiedLast ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copiedLast ? Design.Colors.success : Design.Colors.textTertiary)
                        .frame(width: 26, height: 26)
                        .background(Design.Colors.fill)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Design.Colors.surface)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Design.Colors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack(spacing: 8) {
            // Dashboard button
            Button(action: { onOpenHistory?() }) {
                HStack(spacing: 6) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Design.Colors.accent)

                    Text("Dashboard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Design.Colors.surface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Design.Colors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Settings button
            Button(action: { onOpenSettings?() }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Design.Colors.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Design.Colors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Quit button
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(Design.Colors.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Design.Colors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    MenuBarView(
        stateManager: AppStateManager(),
        hotkeyManager: HotkeyManager(),
        outputDispatcher: OutputDispatcher()
    )
}
