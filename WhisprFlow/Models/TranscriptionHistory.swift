import Foundation

// MARK: - Transcription Entry

/// Represents a single transcription entry in history
struct TranscriptionEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    let duration: TimeInterval? // Recording duration in seconds
    let wordCount: Int
    
    init(id: UUID = UUID(), text: String, timestamp: Date = Date(), duration: TimeInterval? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.wordCount = text.split(separator: " ").count
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    var relativeDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(timestamp) {
            return "Today"
        } else if calendar.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: timestamp)
        }
    }
}

/// Manages transcription history persistence and retrieval
@Observable
final class HistoryStore {
    private(set) var entries: [TranscriptionEntry] = []
    private let storageKey = "whisprflow_history"
    private let maxAgeDays = 7
    
    // Stats
    var todayWordCount: Int {
        let calendar = Calendar.current
        return entries
            .filter { calendar.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + $1.wordCount }
    }
    
    var weekWordCount: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }
    
    var todayEntryCount: Int {
        let calendar = Calendar.current
        return entries.filter { calendar.isDateInToday($0.timestamp) }.count
    }
    
    var totalEntries: Int {
        entries.count
    }
    
    var totalWords: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }
    
    /// Estimated time saved (avg typing speed: 40 words per minute, speaking: 150 wpm)
    /// So for each word transcribed, you save about 1.5 - 0.4 = ~1.1 seconds
    var estimatedTimeSavedMinutes: Int {
        let wordsPerMinuteTyping = 40.0
        let typingTimeMinutes = Double(totalWords) / wordsPerMinuteTyping
        return Int(typingTimeMinutes)
    }
    
    var formattedTimeSaved: String {
        let minutes = estimatedTimeSavedMinutes
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMins = minutes % 60
            if remainingMins == 0 {
                return "\(hours) hr"
            }
            return "\(hours) hr \(remainingMins) min"
        }
    }
    
    var averageWordsPerEntry: Int {
        guard !entries.isEmpty else { return 0 }
        return totalWords / entries.count
    }
    
    /// Get the most recent transcription entry
    var lastEntry: TranscriptionEntry? {
        entries.first
    }
    
    /// Calculate current streak of consecutive days with transcriptions
    var currentStreak: Int {
        guard !entries.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())
        
        // Group entries by day
        let entriesByDay = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        
        // Check if today has entries, if not start from yesterday
        if entriesByDay[currentDate] == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                return 0
            }
            currentDate = yesterday
        }
        
        // Count consecutive days backwards
        while entriesByDay[currentDate] != nil {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                break
            }
            currentDate = previousDay
        }
        
        return streak
    }
    
    /// Get recent entries (last N entries)
    func recentEntries(limit: Int = 5) -> [TranscriptionEntry] {
        Array(entries.prefix(limit))
    }
    
    init() {
        load()
        cleanOldEntries()
    }
    
    // MARK: - Public Methods
    
    func addEntry(_ text: String, duration: TimeInterval? = nil) {
        let entry = TranscriptionEntry(text: text, duration: duration)
        entries.insert(entry, at: 0)
        save()
        logToFile("[HistoryStore] Added entry: \(text.prefix(50))...")
    }
    
    func deleteEntry(_ entry: TranscriptionEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }
    
    func clearHistory() {
        entries.removeAll()
        save()
    }
    
    /// Group entries by date for display
    func entriesGroupedByDate() -> [(date: String, entries: [TranscriptionEntry])] {
        let grouped = Dictionary(grouping: entries) { $0.relativeDate }
        
        // Sort by most recent first
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            guard let first1 = grouped[key1]?.first?.timestamp,
                  let first2 = grouped[key2]?.first?.timestamp else {
                return false
            }
            return first1 > first2
        }
        
        return sortedKeys.map { (date: $0, entries: grouped[$0] ?? []) }
    }
    
    // MARK: - Persistence
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logToFile("[HistoryStore] Failed to save: \(error)")
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }
        
        do {
            entries = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
        } catch {
            logToFile("[HistoryStore] Failed to load: \(error)")
        }
    }
    
    private func cleanOldEntries() {
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -maxAgeDays, to: Date()) ?? Date()
        
        let oldCount = entries.count
        entries.removeAll { $0.timestamp < cutoffDate }
        
        if entries.count != oldCount {
            save()
            logToFile("[HistoryStore] Cleaned \(oldCount - entries.count) old entries")
        }
    }
}
