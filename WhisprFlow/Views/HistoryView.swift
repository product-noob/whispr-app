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
    @State private var searchText: String = ""
    
    // Settings state
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var selectedHotkey: HotkeyManager.HotkeyType = .controlSpace
    @State private var selectedOutputMode: OutputDispatcher.OutputMode = .paste
    @State private var selectedModel: TranscriptionModel = .openAI
    @State private var doubleTapHandsFree: Bool = true
    @State private var fillerWordRemoval: Bool = true
    @State private var smartSpacing: Bool = true
    @State private var personalDictionary: [DictionaryEntry] = []
    @State private var launchAtLogin: Bool = false
    @State private var isDownloadingModel = false
    @State private var downloadingModelId: TranscriptionModel?
    @State private var downloadProgress: Double = 0
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
            
            Divider()
                .background(Design.Colors.border)
            
            // Main content
            mainContent
        }
        .frame(minWidth: 750, maxWidth: .infinity, minHeight: 550, maxHeight: .infinity)
        .background(Design.Colors.background)
        .onAppear {
            loadSettings()
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo/Title
            HStack(spacing: 8) {
                Image("WhisprIcon")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Whispr")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Design.Colors.textPrimary)
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
        .background(Design.Colors.background)
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
            .foregroundStyle(selectedTab == tab ? Design.Colors.accent : Design.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selectedTab == tab ? Design.Colors.accent.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var streakIndicator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(historyStore.currentStreak > 0 ? Color.orange : Design.Colors.disabled)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(historyStore.currentStreak)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text(historyStore.currentStreak == 1 ? "day streak" : "day streak")
                        .font(.system(size: 10))
                        .foregroundStyle(Design.Colors.textTertiary)
                }
            }
            
            if historyStore.currentStreak > 0 {
                Text(streakMotivation)
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            historyStore.currentStreak > 0 
                ? Color.orange.opacity(0.1)
                : Design.Colors.surface
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    historyStore.currentStreak > 0 
                        ? Color.orange.opacity(0.3) 
                        : Design.Colors.border,
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
                        .foregroundStyle(Design.Colors.textPrimary)
                    
                    Text("Voice-to-text transcription at your fingertips")
                        .font(.system(size: 16))
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .padding(.bottom, 8)
                
                // Metrics Cards
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR STATS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Design.Colors.textTertiary)
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
                            color: Design.Colors.accent
                        )
                        metricCard(
                            value: historyStore.formattedTimeSaved,
                            label: "Time Saved",
                            icon: "clock.arrow.circlepath",
                            color: Design.Colors.success
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
                        .foregroundStyle(Design.Colors.textTertiary)
                        .tracking(0.5)
                    
                    HStack(spacing: 8) {
                        compactActionButton(
                            icon: "mic.fill",
                            title: "Record",
                            color: Design.Colors.success,
                            action: { onStartRecording?() }
                        )
                        
                        compactActionButton(
                            icon: "clock.fill",
                            title: "History",
                            color: Design.Colors.accent,
                            action: { selectedTab = "history" }
                        )
                        
                        compactActionButton(
                            icon: "gearshape.fill",
                            title: "Settings",
                            color: Design.Colors.textSecondary,
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
                    .foregroundStyle(Design.Colors.textPrimary)
                
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Design.Colors.border, lineWidth: 1)
        )
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT ACTIVITY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Design.Colors.textTertiary)
                    .tracking(0.5)
                
                Spacer()
                
                if !historyStore.entries.isEmpty {
                    Button(action: { selectedTab = "history" }) {
                        Text("View All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Design.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if historyStore.entries.isEmpty {
                VStack(spacing: 8) {
                    Image("WhisprIcon")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(0.5)
                    
                    Text("No transcriptions yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.textTertiary)
                    
                    Text("Hold \(hotkeyManager.currentHotkey.displayName) to start dictating")
                        .font(.system(size: 12))
                        .foregroundStyle(Design.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Design.Colors.surfaceSecondary)
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
                    .foregroundStyle(Design.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Design.Colors.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Design.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func statusCard(_ title: String, isConfigured: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(isConfigured ? Design.Colors.success : Color.orange)
            
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(isConfigured ? Design.Colors.success.opacity(0.1) : Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func shortcutRow(_ action: String, shortcut: String) -> some View {
        HStack {
            Text(action)
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.textPrimary)
            
            Spacer()
            
            Text(shortcut)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Design.Colors.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Design.Colors.accent.opacity(0.1))
                .cornerRadius(4)
        }
    }
    
    private func recentEntryRow(_ entry: TranscriptionEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.formattedTime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Design.Colors.textTertiary)
            
            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.textPrimary)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: { copyToClipboard(entry.text) }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Design.Colors.surface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Design.Colors.border, lineWidth: 1)
        )
    }
    
    // MARK: - History Tab
    
    /// Entries filtered by search text
    private var filteredEntries: [TranscriptionEntry] {
        if searchText.isEmpty {
            return historyStore.entries
        }
        return historyStore.entries.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Group filtered entries by date
    private var filteredGroupedEntries: [(date: String, entries: [TranscriptionEntry])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        var groups: [(date: String, entries: [TranscriptionEntry])] = []
        var currentDate = ""
        var currentEntries: [TranscriptionEntry] = []

        for entry in filteredEntries {
            let dateStr = formatter.string(from: entry.timestamp)
            if dateStr != currentDate {
                if !currentEntries.isEmpty {
                    groups.append((date: currentDate, entries: currentEntries))
                }
                currentDate = dateStr
                currentEntries = [entry]
            } else {
                currentEntries.append(entry)
            }
        }
        if !currentEntries.isEmpty {
            groups.append((date: currentDate, entries: currentEntries))
        }
        return groups
    }

    private var historyTabContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcription History")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Your transcriptions from the last 7 days")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Colors.textSecondary)
                }

                Spacer()

                // Stats badges
                HStack(spacing: 12) {
                    statBadge(icon: "doc.text", value: "\(historyStore.entries.count)", label: "entries", color: Design.Colors.accent)
                    statBadge(icon: "text.word.spacing", value: "\(historyStore.weekWordCount)", label: "words", color: Design.Colors.success)
                }
            }
            .padding(24)

            // F11: Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.textTertiary)

                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Design.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Design.Colors.surfaceSecondary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Design.Colors.border, lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()
                .background(Design.Colors.border)

            // History list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if filteredEntries.isEmpty {
                        if searchText.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Design.Colors.textTertiary)

                                Text("No results for \"\(searchText)\"")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Design.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    } else {
                        ForEach(filteredGroupedEntries, id: \.date) { group in
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
                .foregroundStyle(Design.Colors.textPrimary)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Design.Colors.fill)
        .cornerRadius(20)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("WhisprIcon")
                .resizable()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(0.5)
            
            Text("No transcriptions yet")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Design.Colors.textSecondary)
            
            Text("Hold \(hotkeyManager.currentHotkey.displayName) to start dictating.\nYour transcriptions will appear here.")
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private func dateSection(_ date: String, entries: [TranscriptionEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(date.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Design.Colors.textTertiary)
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
                .foregroundStyle(Design.Colors.textTertiary)
                .frame(width: 70, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                
                Text("\(entry.wordCount) words")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
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
                        .foregroundStyle(copiedEntryId == entry.id ? .green : Design.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Design.Colors.fill)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: { historyStore.deleteEntry(entry) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Design.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Design.Colors.fill)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Design.Colors.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Design.Colors.border, lineWidth: 1)
        )
    }
    
    // MARK: - Settings Tab
    
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader
                settingsModelSection
                settingsAPISection
                settingsRecordingSection
                settingsOutputSection
                settingsGeneralSection
                settingsStatusSection
                settingsAboutSection
            }
            .padding(24)
        }
        .onChange(of: selectedModel) { _, newValue in
            ConfigStore.shared.update { $0.selectedModel = newValue.rawValue }
            NotificationCenter.default.post(name: .whisprModelChanged, object: nil)
            logToFile("[HistoryView] Model auto-saved: \(newValue.rawValue)")
        }
        .onChange(of: selectedHotkey) { _, newValue in
            hotkeyManager.setHotkey(newValue)
            logToFile("[HistoryView] Hotkey auto-saved: \(newValue.displayName)")
        }
        .onChange(of: selectedOutputMode) { _, newValue in
            outputDispatcher.outputMode = newValue
            logToFile("[HistoryView] Output mode auto-saved: \(newValue.displayName)")
        }
        .onChange(of: doubleTapHandsFree) { _, newValue in
            ConfigStore.shared.update { $0.doubleTapHandsFree = newValue }
            logToFile("[HistoryView] Double-tap hands-free auto-saved: \(newValue)")
        }
        .onChange(of: fillerWordRemoval) { _, newValue in
            ConfigStore.shared.update { $0.fillerWordRemoval = newValue }
            logToFile("[HistoryView] Filler word removal auto-saved: \(newValue)")
        }
        .onChange(of: smartSpacing) { _, newValue in
            ConfigStore.shared.update { $0.smartSpacing = newValue }
            logToFile("[HistoryView] Smart spacing auto-saved: \(newValue)")
        }
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLogin.isEnabled = newValue
            ConfigStore.shared.update { $0.launchAtLogin = newValue }
            logToFile("[HistoryView] Launch at login auto-saved: \(newValue)")
        }
        .onChange(of: personalDictionary) { _, newValue in
            ConfigStore.shared.update { $0.personalDictionary = newValue }
            logToFile("[HistoryView] Personal dictionary auto-saved")
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Design.Colors.textPrimary)

            Text("Changes are saved automatically")
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .padding(.bottom, 8)
    }

    private var settingsModelSection: some View {
        settingsSection("Transcription Model") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(TranscriptionModel.allCases) { model in
                    settingsModelRow(model)
                }

                Text("Local models run on-device — no internet or API key needed")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var settingsAPISection: some View {
        settingsSection("API Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                Text("OpenAI API Key")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)

                HStack(spacing: 8) {
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
                                .foregroundStyle(Design.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Design.Colors.surfaceSecondary)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Design.Colors.border, lineWidth: 1)
                    )

                    Button(action: saveAPIKey) {
                        Text("Save Key")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Design.Colors.accent)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                Text(selectedModel.isLocal ? "Only needed if you switch to OpenAI model" : "Required for cloud transcription")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
            }
        }
    }

    private var settingsRecordingSection: some View {
        settingsSection("Recording") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recording Hotkey")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)

                Picker("", selection: $selectedHotkey) {
                    ForEach(HotkeyManager.HotkeyType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Text("Hold this key combination to record audio.")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)

                Divider()

                settingsToggleRow(
                    title: "Double-tap for hands-free mode",
                    subtitle: "Double-tap hotkey to start, press any key to stop",
                    isOn: $doubleTapHandsFree
                )
            }
        }
    }

    private var settingsOutputSection: some View {
        settingsSection("Output & Processing") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Output Mode")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)

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
                    .foregroundStyle(Design.Colors.textTertiary)

                Divider()

                settingsToggleRow(
                    title: "Remove filler words",
                    subtitle: "Automatically removes \"uh\", \"um\", \"like,\" etc.",
                    isOn: $fillerWordRemoval
                )

                Divider()

                settingsToggleRow(
                    title: "Smart paste spacing",
                    subtitle: "Auto-prepend a space when pasting mid-sentence",
                    isOn: $smartSpacing
                )

                Divider()

                personalDictionarySection
            }
        }
    }

    private var personalDictionarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Personal Dictionary")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)

                Spacer()

                Button {
                    personalDictionary.append(DictionaryEntry(word: "", replacement: ""))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Design.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            if !personalDictionary.isEmpty {
                VStack(spacing: 6) {
                    ForEach($personalDictionary) { $entry in
                        HStack(spacing: 8) {
                            TextField("Word", text: $entry.word)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .padding(6)
                                .background(Design.Colors.surface)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Design.Colors.border, lineWidth: 1))

                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Design.Colors.textTertiary)

                            TextField("Replacement", text: $entry.replacement)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .padding(6)
                                .background(Design.Colors.surface)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Design.Colors.border, lineWidth: 1))

                            Button {
                                personalDictionary.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Design.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text("Words will be fuzzy-matched and replaced in transcriptions")
                .font(.system(size: 11))
                .foregroundStyle(Design.Colors.textTertiary)
        }
    }

    private var settingsGeneralSection: some View {
        settingsSection("General") {
            settingsToggleRow(
                title: "Launch at Login",
                subtitle: "Start Whispr automatically when you log in",
                isOn: $launchAtLogin
            )
        }
    }

    private var settingsStatusSection: some View {
        settingsSection("Status & Permissions") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    statusCard("API Key", isConfigured: selectedModel.isLocal || KeychainHelper.hasAPIKey)
                    statusCard("Microphone", isConfigured: true)
                    statusCard("Accessibility", isConfigured: hotkeyManager.hasAccessibilityPermission)
                }

                Divider()

                permissionRow("Microphone Access", isGranted: true, action: {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                })

                permissionRow("Accessibility", isGranted: hotkeyManager.hasAccessibilityPermission, action: {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                })
            }
        }
    }

    private var settingsAboutSection: some View {
        settingsSection("About") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Version")
                        .foregroundStyle(Design.Colors.textSecondary)
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .font(.system(size: 13))

                Divider()

                HStack {
                    Text("Developed by")
                        .foregroundStyle(Design.Colors.textSecondary)
                    Spacer()
                    Button(action: {
                        if let url = URL(string: "https://princejain.me") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("Prince Jain")
                                .foregroundStyle(Design.Colors.accent)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                                .foregroundStyle(Design.Colors.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 13))

                HStack {
                    Text("Status")
                        .foregroundStyle(Design.Colors.textSecondary)
                    Spacer()
                    Text(TrialTracker.shared.trialStatusMessage)
                        .foregroundStyle(Design.Colors.textPrimary)
                }
                .font(.system(size: 13))
            }
        }
    }

    // MARK: - Settings Helpers

    private func settingsModelRow(_ model: TranscriptionModel) -> some View {
        let isSelected = selectedModel == model
        let isAvailable = model == .openAI || ModelManager.shared.isModelAvailable(model)
        let isDownloading = downloadingModelId == model

        return HStack(spacing: 10) {
            // Radio button — selects model (only if available or openAI)
            Button {
                if isAvailable {
                    selectedModel = model
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Design.Colors.accent : Design.Colors.disabled)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable && model.isLocal)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .medium))
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
                }

                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)

                // Download progress bar
                if isDownloading {
                    ProgressView(value: downloadProgress)
                        .tint(Design.Colors.accent)
                        .frame(maxWidth: 200)
                }
            }

            Spacer()

            if model.isLocal {
                if isAvailable {
                    Text("Ready")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Design.Colors.success)
                } else if isDownloading {
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Design.Colors.accent)
                } else {
                    Button {
                        downloadModel(model)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 11))
                            Text("Download")
                                .font(.system(size: 11, weight: .medium))
                            Text("(\(model.downloadSizeMB) MB)")
                                .font(.system(size: 10))
                                .foregroundStyle(Design.Colors.textTertiary)
                        }
                        .foregroundStyle(Design.Colors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Design.Colors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(isSelected ? Design.Colors.accent.opacity(0.06) : Color.clear)
        .cornerRadius(8)
    }

    private func downloadModel(_ model: TranscriptionModel) {
        downloadingModelId = model
        downloadProgress = 0

        Task {
            do {
                try await ModelManager.shared.downloadModel(model) { progress, _ in
                    Task { @MainActor in
                        downloadProgress = progress
                    }
                }
                await MainActor.run {
                    downloadingModelId = nil
                    downloadProgress = 0
                    // Auto-select after download
                    selectedModel = model
                }
            } catch {
                await MainActor.run {
                    downloadingModelId = nil
                    downloadProgress = 0
                    logToFile("[HistoryView] Model download failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func settingsToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.textTertiary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
    
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Design.Colors.textTertiary)
                .tracking(0.5)
            
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Design.Colors.surfaceSecondary)
            .cornerRadius(12)
        }
    }
    
    private func permissionRow(_ title: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? Design.Colors.success : Color.orange)
            
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.textPrimary)
            
            Spacer()
            
            Button(action: action) {
                Text(isGranted ? "Granted" : "Open Settings")
                    .font(.system(size: 12))
                    .foregroundStyle(isGranted ? Design.Colors.success : Design.Colors.accent)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Settings Logic
    
    private func loadSettings() {
        let config = ConfigStore.shared.config
        apiKey = KeychainHelper.getAPIKey() ?? ""
        selectedHotkey = hotkeyManager.currentHotkey
        selectedOutputMode = outputDispatcher.outputMode
        selectedModel = TranscriptionModel(rawValue: config.selectedModel) ?? .openAI
        doubleTapHandsFree = config.doubleTapHandsFree
        fillerWordRemoval = config.fillerWordRemoval
        smartSpacing = config.smartSpacing
        personalDictionary = config.personalDictionary
        launchAtLogin = config.launchAtLogin
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty, apiKey.hasPrefix("sk-") else {
            logToFile("[HistoryView] Invalid API key — must start with sk-")
            return
        }
        _ = KeychainHelper.saveAPIKey(apiKey)
        logToFile("[HistoryView] API key saved")
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
