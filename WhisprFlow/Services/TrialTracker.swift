import Foundation

/// Tracks trial usage for the BYOK (Bring Your Own Key) model
/// Users get 20 free transcriptions OR 1 day, then need to add their own OpenAI API key
@Observable
final class TrialTracker {
    static let shared = TrialTracker()
    
    private let maxTrialTranscriptions = 20
    private let maxTrialDays = 1
    
    private let firstLaunchKey = "whisprflow_first_launch"
    private let transcriptionCountKey = "whisprflow_trial_count"
    
    private(set) var transcriptionsUsed: Int = 0
    private(set) var firstLaunchDate: Date?
    
    init() {
        load()
    }
    
    // MARK: - Public Properties
    
    /// Whether the trial period is still active
    var isTrialActive: Bool {
        // If user has their own key configured, trial status doesn't matter
        if KeychainHelper.hasAPIKey {
            return false // Not using trial, using own key
        }
        
        // Check both limits
        return !hasExceededTranscriptionLimit && !hasExceededTimeLimit
    }
    
    /// Whether trial has ended and user needs to add their own key
    var trialEnded: Bool {
        return hasExceededTranscriptionLimit || hasExceededTimeLimit
    }
    
    /// Number of transcriptions remaining in trial
    var transcriptionsRemaining: Int {
        return max(0, maxTrialTranscriptions - transcriptionsUsed)
    }
    
    /// Whether user can transcribe (either trial active OR has own key)
    var canTranscribe: Bool {
        return isTrialActive || KeychainHelper.hasAPIKey
    }
    
    /// Human-readable trial status for UI
    var trialStatusMessage: String {
        if KeychainHelper.hasAPIKey {
            return "Using your API key"
        }
        
        if trialEnded {
            return "Trial ended"
        }
        
        let remaining = transcriptionsRemaining
        if remaining == 1 {
            return "1 free transcription left"
        }
        return "\(remaining) free transcriptions left"
    }
    
    // MARK: - Private Properties
    
    private var hasExceededTranscriptionLimit: Bool {
        return transcriptionsUsed >= maxTrialTranscriptions
    }
    
    private var hasExceededTimeLimit: Bool {
        guard let firstLaunch = firstLaunchDate else { return false }
        let daysSinceFirstLaunch = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        return daysSinceFirstLaunch >= maxTrialDays
    }
    
    // MARK: - Public Methods
    
    /// Record a successful transcription (call after transcription completes)
    func recordTranscription() {
        // Only count against trial if using trial key
        if !KeychainHelper.hasAPIKey {
            transcriptionsUsed += 1
            save()
            logToFile("[TrialTracker] Recorded transcription. Used: \(transcriptionsUsed)/\(maxTrialTranscriptions)")
        }
    }
    
    /// Get the appropriate API key to use
    func getAPIKey() -> String? {
        // Prefer user's own key
        if let userKey = KeychainHelper.getAPIKey(), !userKey.isEmpty {
            return userKey
        }
        
        // Fall back to trial key if trial is active
        if isTrialActive {
            return ObfuscatedKey.trialKey
        }
        
        return nil
    }
    
    /// Check if we should show the "add your key" prompt
    var shouldShowAddKeyPrompt: Bool {
        return trialEnded && !KeychainHelper.hasAPIKey
    }
    
    // MARK: - Persistence
    
    private func load() {
        // Load first launch date
        if let timestamp = UserDefaults.standard.object(forKey: firstLaunchKey) as? Double {
            firstLaunchDate = Date(timeIntervalSince1970: timestamp)
        } else {
            // First launch - record it
            firstLaunchDate = Date()
            UserDefaults.standard.set(firstLaunchDate!.timeIntervalSince1970, forKey: firstLaunchKey)
            logToFile("[TrialTracker] First launch recorded")
        }
        
        // Load transcription count
        transcriptionsUsed = UserDefaults.standard.integer(forKey: transcriptionCountKey)
        logToFile("[TrialTracker] Loaded: \(transcriptionsUsed) transcriptions used, first launch: \(firstLaunchDate?.description ?? "unknown")")
    }
    
    private func save() {
        UserDefaults.standard.set(transcriptionsUsed, forKey: transcriptionCountKey)
    }
    
    // MARK: - Debug (remove in production if desired)
    
    #if DEBUG
    func resetTrial() {
        transcriptionsUsed = 0
        firstLaunchDate = Date()
        UserDefaults.standard.set(firstLaunchDate!.timeIntervalSince1970, forKey: firstLaunchKey)
        UserDefaults.standard.set(0, forKey: transcriptionCountKey)
        logToFile("[TrialTracker] Trial reset for debugging")
    }
    #endif
}
