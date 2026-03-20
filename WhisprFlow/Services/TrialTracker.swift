import Foundation

/// Tracks trial usage for the BYOK (Bring Your Own Key) model
/// Users get 20 free transcriptions OR 1 day, then need to add their own OpenAI API key
@Observable
final class TrialTracker {
    static let shared = TrialTracker()

    private let maxTrialTranscriptions = 20
    private let maxTrialDays = 1

    private(set) var transcriptionsUsed: Int = 0
    private(set) var firstLaunchDate: Date?

    init() {
        load()
    }

    // MARK: - Public Properties

    /// Whether the user is on a local model (no trial needed)
    var isUsingLocalModel: Bool {
        let model = TranscriptionModel(rawValue: ConfigStore.shared.config.selectedModel)
        return model?.isLocal ?? false
    }

    /// Whether the trial period is still active
    var isTrialActive: Bool {
        if KeychainHelper.hasAPIKey { return false }
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

    /// Whether user can transcribe (local model, trial active, OR has own key)
    var canTranscribe: Bool {
        if isUsingLocalModel { return true }
        return isTrialActive || KeychainHelper.hasAPIKey
    }

    /// Human-readable trial status for UI
    var trialStatusMessage: String {
        if isUsingLocalModel { return "Using local model" }
        if KeychainHelper.hasAPIKey { return "Using your API key" }
        if trialEnded { return "Trial ended" }

        let remaining = transcriptionsRemaining
        if remaining == 1 { return "1 free transcription left" }
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
        if !KeychainHelper.hasAPIKey && !isUsingLocalModel {
            transcriptionsUsed += 1
            save()
            logToFile("[TrialTracker] Recorded transcription. Used: \(transcriptionsUsed)/\(maxTrialTranscriptions)")
        }
    }

    /// Get the appropriate API key to use
    func getAPIKey() -> String? {
        if let userKey = KeychainHelper.getAPIKey(), !userKey.isEmpty {
            return userKey
        }
        if isTrialActive {
            return ObfuscatedKey.trialKey
        }
        return nil
    }

    /// Check if we should show the "add your key" prompt
    var shouldShowAddKeyPrompt: Bool {
        if isUsingLocalModel { return false }
        return trialEnded && !KeychainHelper.hasAPIKey
    }

    // MARK: - Persistence (ConfigStore-backed)

    private func load() {
        let config = ConfigStore.shared.config

        if let timestamp = config.trialFirstLaunch {
            firstLaunchDate = Date(timeIntervalSince1970: timestamp)
        } else {
            firstLaunchDate = Date()
            ConfigStore.shared.update { $0.trialFirstLaunch = Date().timeIntervalSince1970 }
            logToFile("[TrialTracker] First launch recorded")
        }

        transcriptionsUsed = config.trialTranscriptionCount
        logToFile("[TrialTracker] Loaded: \(transcriptionsUsed) transcriptions used, first launch: \(firstLaunchDate?.description ?? "unknown")")
    }

    private func save() {
        ConfigStore.shared.update { $0.trialTranscriptionCount = self.transcriptionsUsed }
    }

    #if DEBUG
    func resetTrial() {
        transcriptionsUsed = 0
        firstLaunchDate = Date()
        ConfigStore.shared.update {
            $0.trialFirstLaunch = Date().timeIntervalSince1970
            $0.trialTranscriptionCount = 0
        }
        logToFile("[TrialTracker] Trial reset for debugging")
    }
    #endif
}
