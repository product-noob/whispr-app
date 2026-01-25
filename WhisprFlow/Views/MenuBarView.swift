import SwiftUI

/// Menu bar popover view - Control panel for WhisprFlow
struct MenuBarView: View {
    @Bindable var stateManager: AppStateManager
    let hotkeyManager: HotkeyManager
    let outputDispatcher: OutputDispatcher
    var historyStore: HistoryStore?
    var onStartRecording: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    
    @State private var selectedTab = "home"
    
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
            
            // Content
            HStack(spacing: 0) {
                // Sidebar
                sidebar
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Main content
                mainContent
            }
        }
        .frame(width: 500, height: 400)
        .background(Color(hex: "1C1C1E"))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            // App icon and name
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: "8B5CF6"))
                
                Text("WhisprFlow")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            // Status indicator
            statusBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateManager.state.isIdle ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var statusText: String {
        switch stateManager.state {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .error: return "Error"
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            sidebarButton("Home", icon: "house.fill", tab: "home")
            sidebarButton("History", icon: "clock.fill", tab: "history")
            sidebarButton("Settings", icon: "gearshape.fill", tab: "settings")
            
            Spacer()
            
            // Quick actions
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Actions")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 12)
                
                quickActionButton("Start Recording", icon: "mic.fill", color: .green) {
                    onStartRecording?()
                }
            }
            .padding(.bottom, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Quit button
            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                    Text("Quit")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .frame(width: 140)
    }
    
    private func sidebarButton(_ title: String, icon: String, tab: String) -> some View {
        Button(action: {
            // Settings and History both open the main dashboard
            if tab == "settings" || tab == "history" {
                onOpenHistory?()
            } else {
                selectedTab = tab
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13))
                
                Spacer()
            }
            .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
    
    private func quickActionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch selectedTab {
            case "home":
                homeView
            case "history":
                historyView
            case "settings":
                settingsQuickView
            default:
                homeView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Home View
    
    private var homeView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Main status
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(hex: "8B5CF6"))
                
                Text("Ready to Transcribe")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text("Hold \(hotkeySymbol) or click the pill to start")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Stats
            HStack(spacing: 24) {
                statItem("Today", value: "\(historyStore?.todayWordCount ?? 0)", unit: "words")
                statItem("This Week", value: "\(historyStore?.weekWordCount ?? 0)", unit: "words")
            }
            .padding(.bottom, 20)
        }
        .padding(20)
    }
    
    private func statItem(_ title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - History View
    
    private var historyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Transcriptions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Button(action: { onOpenHistory?() }) {
                    Text("View All")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "8B5CF6"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            if let entries = historyStore?.entries, !entries.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(entries.prefix(5)) { entry in
                            recentEntryRow(entry)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No transcriptions yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func recentEntryRow(_ entry: TranscriptionEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.formattedTime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            
            Text(entry.text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
            
            Spacer()
            
            Button(action: {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(entry.text, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Settings Quick View
    
    private var settingsQuickView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Settings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            
            VStack(spacing: 12) {
                settingsRow("Hotkey", value: hotkeyDisplayName)
                settingsRow("Output Mode", value: outputDispatcher.outputMode.displayName)
                settingsRow("API Status", value: KeychainHelper.hasAPIKey ? "Connected" : "Not configured")
            }
            
            Spacer()
            
            Button(action: { onOpenHistory?() }) {
                HStack {
                    Text("Open Dashboard")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(12)
                .background(Color(hex: "8B5CF6"))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }
    
    private func settingsRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.white)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    MenuBarView(
        stateManager: AppStateManager(),
        hotkeyManager: HotkeyManager(),
        outputDispatcher: OutputDispatcher()
    )
}
