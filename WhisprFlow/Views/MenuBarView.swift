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
    
    // Get hotkey display from the actual manager
    private var hotkeyDisplayName: String {
        hotkeyManager.currentHotkey.displayName
    }
    
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
            // Header
            header
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Main content
            ScrollView {
                VStack(spacing: 14) {
                    // Trial status (if using trial)
                    if !KeychainHelper.hasAPIKey {
                        trialStatusBanner
                    }
                    
                    // Recording Section
                    recordingSection
                    
                    // Today's Stats
                    todayStats
                    
                    // Last Transcription Preview
                    if let lastEntry = historyStore?.lastEntry {
                        lastTranscriptionSection(lastEntry)
                    }
                    
                    // Footer Actions
                    footerActions
                }
                .padding(16)
            }
        }
        .frame(width: 300, height: 420)
        .background(Color(hex: "1C1C1E"))
    }
    
    // MARK: - Trial Status Banner
    
    private var trialStatusBanner: some View {
        let tracker = TrialTracker.shared
        let used = tracker.transcriptionsUsed
        let total = 20
        let remaining = tracker.transcriptionsRemaining
        
        return VStack(spacing: 8) {
            HStack {
                Image(systemName: "gift.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "8B5CF6"))
                
                Text("Free Trial")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("\(remaining)/\(total) left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(remaining <= 5 ? Color.orange : Color(hex: "8B5CF6"))
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            remaining <= 5 
                                ? Color.orange 
                                : Color(hex: "8B5CF6")
                        )
                        .frame(width: geometry.size.width * CGFloat(remaining) / CGFloat(total), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            // App icon and name
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "8B5CF6"))
                
                Text("Whispr")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            // Status badge
            statusBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(stateManager.state.isIdle ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var statusText: String {
        switch stateManager.state {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .error: return "Error"
        }
    }
    
    // MARK: - Recording Section
    
    private var recordingSection: some View {
        VStack(spacing: 12) {
            Text("Hold \(hotkeySymbol) to start recording")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            
            Button(action: { onStartRecording?() }) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                    
                    Text("Start Recording")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: "10B981"))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Today's Stats
    
    private var todayStats: some View {
        HStack(spacing: 16) {
            statPill(
                value: "\(historyStore?.todayEntryCount ?? 0)",
                label: "entries"
            )
            
            Text("•")
                .foregroundStyle(.white.opacity(0.3))
            
            statPill(
                value: "\(historyStore?.todayWordCount ?? 0)",
                label: "words"
            )
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func statPill(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
    
    // MARK: - Last Transcription
    
    private func lastTranscriptionSection(_ entry: TranscriptionEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                
                Spacer()
                
                Text(entry.formattedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            
            HStack(alignment: .top, spacing: 12) {
                Text(entry.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
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
                        .font(.system(size: 12))
                        .foregroundStyle(copiedLast ? Color.green : .white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
    
    // MARK: - Footer Actions
    
    private var footerActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: { onOpenHistory?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.grid.1x2")
                            .font(.system(size: 11))
                        
                        Text("Open Dashboard")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "8B5CF6"))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                            .font(.system(size: 11))
                        
                        Text("Quit")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            // Attribution
            Button(action: {
                if let url = URL(string: "https://princejain.me") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("Made by Prince Jain")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
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
