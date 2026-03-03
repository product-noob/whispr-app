import SwiftUI
import AppKit

/// Main dashboard view with Home, History, and Settings tabs
struct HistoryView: View {
    @Bindable var historyStore: HistoryStore
    let hotkeyManager: HotkeyManager
    let outputDispatcher: OutputDispatcher
    var onStartRecording: (() -> Void)?
    var onClose: (() -> Void)?
    
    @State private var selectedTab = "home"
    @State private var copiedEntryId: UUID?
    
    // Settings state
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var selectedHotkey: HotkeyManager.HotkeyType = .controlSpace
    @State private var selectedOutputMode: OutputDispatcher.OutputMode = .paste
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
            
            Divider()
                .background(Color(hex: "E5E5E5"))
            
            // Main content
            mainContent
        }
        .frame(minWidth: 750, minHeight: 550)
        .background(Color.white)
        .onAppear {
            loadSettings()
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo/Title
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: "8B5CF6"))
                
                Text("Whispr")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "1F2937"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            
            // Navigation items
            VStack(spacing: 4) {
                sidebarItem("Home", icon: "house.fill", tab: "home")
                sidebarItem("History", icon: "clock.fill", tab: "history")
                sidebarItem("Settings", icon: "gearshape.fill", tab: "settings")
            }
            .padding(.horizontal, 8)
            
            Spacer()
            
            // Streak indicator at bottom
            streakIndicator
                .padding(12)
        }
        .frame(width: 200)
        .background(Color(hex: "FAFAFA"))
    }
    
    private func sidebarItem(_ title: String, icon: String, tab: String) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 14))
                
                Spacer()
            }
            .foregroundStyle(selectedTab == tab ? Color(hex: "8B5CF6") : Color(hex: "6B7280"))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selectedTab == tab ? Color(hex: "8B5CF6").opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var streakIndicator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(historyStore.currentStreak > 0 ? Color.orange : Color(hex: "D1D5DB"))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(historyStore.currentStreak)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(hex: "1F2937"))
                    Text(historyStore.currentStreak == 1 ? "day streak" : "day streak")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                }
            }
            
            if historyStore.currentStreak > 0 {
                Text(streakMotivation)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "6B7280"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            historyStore.currentStreak > 0 
                ? Color.orange.opacity(0.1) 
                : Color.white
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    historyStore.currentStreak > 0 
                        ? Color.orange.opacity(0.3) 
                        : Color(hex: "E5E5E5"),
                    lineWidth: 1
                )
        )
    }
    
    private var streakMotivation: String {
        let streak = historyStore.currentStreak
        if streak >= 30 { return "Incredible! 🔥" }
        if streak >= 14 { return "On fire! Keep going!" }
        if streak >= 7 { return "One week strong!" }
        if streak >= 3 { return "Building momentum!" }
        return "Great start!"
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch selectedTab {
            case "home":
                homeContent
            case "history":
                historyTabContent
            case "settings":
                settingsContent
            default:
                homeContent
            }
        }
    }
    
    // MARK: - Home Tab
    
    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Welcome header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to Whispr")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(hex: "1F2937"))
                    
                    Text("Voice-to-text transcription at your fingertips")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "6B7280"))
                }
                .padding(.bottom, 8)
                
                // Metrics Cards
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR STATS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                        .tracking(0.5)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        metricCard(
                            value: "\(historyStore.totalWords)",
                            label: "Total Words",
                            icon: "text.word.spacing",
                            color: Color(hex: "8B5CF6")
                        )
                        metricCard(
                            value: historyStore.formattedTimeSaved,
                            label: "Time Saved",
                            icon: "clock.arrow.circlepath",
                            color: Color(hex: "10B981")
                        )
                        metricCard(
                            value: "\(historyStore.totalEntries)",
                            label: "Transcriptions",
                            icon: "waveform",
                            color: Color(hex: "F59E0B")
                        )
                    }
                }
                
                // Recent Activity
                recentActivitySection
                
                // Quick Actions (compact)
                VStack(alignment: .leading, spacing: 12) {
                    Text("QUICK ACTIONS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                        .tracking(0.5)
                    
                    HStack(spacing: 8) {
                        compactActionButton(
                            icon: "mic.fill",
                            title: "Record",
                            color: Color(hex: "10B981"),
                            action: { onStartRecording?() }
                        )
                        
                        compactActionButton(
                            icon: "clock.fill",
                            title: "History",
                            color: Color(hex: "8B5CF6"),
                            action: { selectedTab = "history" }
                        )
                        
                        compactActionButton(
                            icon: "gearshape.fill",
                            title: "Settings",
                            color: Color(hex: "6B7280"),
                            action: { selectedTab = "settings" }
                        )
                    }
                }
            }
            .padding(24)
        }
    }
    
    private func metricCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "1F2937"))
                
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "9CA3AF"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
        )
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT ACTIVITY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "9CA3AF"))
                    .tracking(0.5)
                
                Spacer()
                
                if !historyStore.entries.isEmpty {
                    Button(action: { selectedTab = "history" }) {
                        Text("View All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "8B5CF6"))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if historyStore.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(hex: "D1D5DB"))
                    
                    Text("No transcriptions yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                    
                    Text("Hold \(hotkeyManager.currentHotkey.displayName) to start dictating")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(hex: "F9FAFB"))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(historyStore.recentEntries(limit: 5)) { entry in
                        recentEntryRow(entry)
                    }
                }
            }
        }
    }
    
    private func compactActionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "1F2937"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func statusCard(_ title: String, isConfigured: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(isConfigured ? Color(hex: "10B981") : Color.orange)
            
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "1F2937"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(isConfigured ? Color(hex: "10B981").opacity(0.1) : Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func shortcutRow(_ action: String, shortcut: String) -> some View {
        HStack {
            Text(action)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "1F2937"))
            
            Spacer()
            
            Text(shortcut)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "8B5CF6"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: "8B5CF6").opacity(0.1))
                .cornerRadius(4)
        }
    }
    
    private func recentEntryRow(_ entry: TranscriptionEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.formattedTime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: "9CA3AF"))
            
            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "1F2937"))
                .lineLimit(1)
            
            Spacer()
            
            Button(action: { copyToClipboard(entry.text) }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "9CA3AF"))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
        )
    }
    
    // MARK: - History Tab
    
    private var historyTabContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcription History")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(hex: "1F2937"))
                    
                    Text("Your transcriptions from the last 7 days")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "6B7280"))
                }
                
                Spacer()
                
                // Stats badges
                HStack(spacing: 12) {
                    statBadge(icon: "doc.text", value: "\(historyStore.entries.count)", label: "entries", color: Color(hex: "8B5CF6"))
                    statBadge(icon: "text.word.spacing", value: "\(historyStore.weekWordCount)", label: "words", color: Color(hex: "10B981"))
                }
            }
            .padding(24)
            
            Divider()
                .background(Color(hex: "E5E5E5"))
            
            // History list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if historyStore.entries.isEmpty {
                        emptyState
                    } else {
                        ForEach(historyStore.entriesGroupedByDate(), id: \.date) { group in
                            dateSection(group.date, entries: group.entries)
                        }
                    }
                }
                .padding(24)
            }
        }
    }
    
    private func statBadge(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "1F2937"))
            
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "9CA3AF"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(hex: "F3F4F6"))
        .cornerRadius(20)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "D1D5DB"))
            
            Text("No transcriptions yet")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(hex: "6B7280"))
            
            Text("Hold \(hotkeyManager.currentHotkey.displayName) to start dictating.\nYour transcriptions will appear here.")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "9CA3AF"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private func dateSection(_ date: String, entries: [TranscriptionEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(date.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "9CA3AF"))
                .tracking(0.5)
            
            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    transcriptionRow(entry)
                }
            }
        }
    }
    
    private func transcriptionRow(_ entry: TranscriptionEntry) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(entry.formattedTime)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color(hex: "9CA3AF"))
                .frame(width: 70, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "1F2937"))
                    .lineLimit(3)
                    .textSelection(.enabled)
                
                Text("\(entry.wordCount) words")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "9CA3AF"))
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: {
                    copyToClipboard(entry.text)
                    copiedEntryId = entry.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedEntryId == entry.id { copiedEntryId = nil }
                    }
                }) {
                    Image(systemName: copiedEntryId == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(copiedEntryId == entry.id ? .green : Color(hex: "9CA3AF"))
                        .frame(width: 28, height: 28)
                        .background(Color(hex: "F3F4F6"))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: { historyStore.deleteEntry(entry) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                        .frame(width: 28, height: 28)
                        .background(Color(hex: "F3F4F6"))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
        )
    }
    
    // MARK: - Settings Tab
    
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(hex: "1F2937"))
                    
                    Text("Configure Whispr to your preferences")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "6B7280"))
                }
                .padding(.bottom, 8)
                
                // API Key Section
                settingsSection("API Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OpenAI API Key")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "374151"))
                        
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
                                    .foregroundStyle(Color(hex: "9CA3AF"))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color(hex: "F9FAFB"))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
                        )
                        
                        Text("Your API key is stored locally and never shared.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "9CA3AF"))
                    }
                }
                
                // Hotkey Section
                settingsSection("Hotkey") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recording Hotkey")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "374151"))
                        
                        Picker("", selection: $selectedHotkey) {
                            ForEach(HotkeyManager.HotkeyType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text("Hold this key combination to record audio.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "9CA3AF"))
                    }
                }
                
                // Output Section
                settingsSection("Output") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Output Mode")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "374151"))
                        
                        Picker("", selection: $selectedOutputMode) {
                            ForEach(OutputDispatcher.OutputMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text(selectedOutputMode == .paste 
                            ? "Text will be automatically pasted into the focused app."
                            : "Text will be copied to clipboard only.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "9CA3AF"))
                    }
                }
                
                // Save Button
                Button(action: saveSettings) {
                    Text("Save Settings")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "8B5CF6"))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Status Section
                settingsSection("Status") {
                    HStack(spacing: 12) {
                        statusCard("API Key", isConfigured: KeychainHelper.hasAPIKey)
                        statusCard("Microphone", isConfigured: true)
                        statusCard("Accessibility", isConfigured: hotkeyManager.hasAccessibilityPermission)
                    }
                }
                
                // Keyboard Shortcuts Section
                settingsSection("Keyboard Shortcuts") {
                    VStack(spacing: 8) {
                        shortcutRow("Start/Stop Recording", shortcut: hotkeyManager.currentHotkey.displayName)
                        shortcutRow("Open Dashboard", shortcut: "Right-click pill")
                    }
                }
                
                // Permissions Section
                settingsSection("Permissions") {
                    VStack(spacing: 12) {
                        permissionRow("Microphone Access", isGranted: true, action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        })
                        
                        permissionRow("Accessibility", isGranted: hotkeyManager.hasAccessibilityPermission, action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        })
                    }
                }
                
                // About Section
                settingsSection("About") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Version")
                                .foregroundStyle(Color(hex: "6B7280"))
                            Spacer()
                            Text("1.0.0")
                                .foregroundStyle(Color(hex: "1F2937"))
                        }
                        .font(.system(size: 13))
                        
                        Divider()
                        
                        // Developer attribution
                        HStack {
                            Text("Developed by")
                                .foregroundStyle(Color(hex: "6B7280"))
                            Spacer()
                            Button(action: {
                                if let url = URL(string: "https://princejain.me") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text("Prince Jain")
                                        .foregroundStyle(Color(hex: "8B5CF6"))
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(hex: "8B5CF6"))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.system(size: 13))
                        
                        // Trial status
                        HStack {
                            Text("Status")
                                .foregroundStyle(Color(hex: "6B7280"))
                            Spacer()
                            Text(TrialTracker.shared.trialStatusMessage)
                                .foregroundStyle(Color(hex: "1F2937"))
                        }
                        .font(.system(size: 13))
                    }
                }
            }
            .padding(24)
        }
    }
    
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "9CA3AF"))
                .tracking(0.5)
            
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "F9FAFB"))
            .cornerRadius(12)
        }
    }
    
    private func permissionRow(_ title: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? Color(hex: "10B981") : Color.orange)
            
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "1F2937"))
            
            Spacer()
            
            Button(action: action) {
                Text(isGranted ? "Granted" : "Open Settings")
                    .font(.system(size: 12))
                    .foregroundStyle(isGranted ? Color(hex: "10B981") : Color(hex: "8B5CF6"))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Settings Logic
    
    private func loadSettings() {
        apiKey = KeychainHelper.getAPIKey() ?? ""
        selectedHotkey = hotkeyManager.currentHotkey
        selectedOutputMode = outputDispatcher.outputMode
    }
    
    private func saveSettings() {
        // Save API key
        if !apiKey.isEmpty {
            _ = KeychainHelper.saveAPIKey(apiKey)
        }
        
        // Save hotkey
        hotkeyManager.setHotkey(selectedHotkey)
        
        // Save output mode
        UserDefaults.standard.set(selectedOutputMode.rawValue, forKey: "outputMode")
        
        logToFile("[HistoryView] Settings saved")
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Preview

#Preview {
    let store = HistoryStore()
    store.addEntry("Hello, this is a test transcription.")
    store.addEntry("Testing the history feature with some longer text.")
    
    return HistoryView(
        historyStore: store,
        hotkeyManager: HotkeyManager(),
        outputDispatcher: OutputDispatcher()
    )
}
