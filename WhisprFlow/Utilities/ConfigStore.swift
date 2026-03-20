import Foundation

// MARK: - Config Data Model

struct DictionaryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var word: String
    var replacement: String
}

struct CodablePoint: Codable {
    var x: Double
    var y: Double
}

struct AppConfig: Codable {
    // Onboarding
    var hasCompletedOnboarding: Bool = false

    // Transcription
    var selectedModel: String = "openai"

    // Hotkey
    var hotkeyType: String = "fn"
    var doubleTapHandsFree: Bool = true

    // Output
    var outputMode: String = "paste"

    // Post-processing
    var fillerWordRemoval: Bool = true
    var personalDictionary: [DictionaryEntry] = []

    // Smart features
    var smartSpacing: Bool = true

    // UI
    var pillPosition: CodablePoint? = nil
    var launchAtLogin: Bool = false

    // Trial (migrated from UserDefaults)
    var trialFirstLaunch: Double? = nil
    var trialTranscriptionCount: Int = 0

    // Coding keys for stable JSON field names
    enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding = "has_completed_onboarding"
        case selectedModel = "selected_model"
        case hotkeyType = "hotkey_type"
        case doubleTapHandsFree = "double_tap_hands_free"
        case outputMode = "output_mode"
        case fillerWordRemoval = "filler_word_removal"
        case personalDictionary = "personal_dictionary"
        case smartSpacing = "smart_spacing"
        case pillPosition = "pill_position"
        case launchAtLogin = "launch_at_login"
        case trialFirstLaunch = "trial_first_launch"
        case trialTranscriptionCount = "trial_transcription_count"
    }

    init() {}

    // Custom decoder with per-field fallback defaults — adding new fields never breaks existing configs
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig()
        hasCompletedOnboarding = (try? c.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? defaults.hasCompletedOnboarding
        selectedModel = (try? c.decode(String.self, forKey: .selectedModel)) ?? defaults.selectedModel
        hotkeyType = (try? c.decode(String.self, forKey: .hotkeyType)) ?? defaults.hotkeyType
        doubleTapHandsFree = (try? c.decode(Bool.self, forKey: .doubleTapHandsFree)) ?? defaults.doubleTapHandsFree
        outputMode = (try? c.decode(String.self, forKey: .outputMode)) ?? defaults.outputMode
        fillerWordRemoval = (try? c.decode(Bool.self, forKey: .fillerWordRemoval)) ?? defaults.fillerWordRemoval
        personalDictionary = (try? c.decode([DictionaryEntry].self, forKey: .personalDictionary)) ?? defaults.personalDictionary
        smartSpacing = (try? c.decode(Bool.self, forKey: .smartSpacing)) ?? defaults.smartSpacing
        pillPosition = try? c.decode(CodablePoint.self, forKey: .pillPosition)
        launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? defaults.launchAtLogin
        trialFirstLaunch = try? c.decode(Double.self, forKey: .trialFirstLaunch)
        trialTranscriptionCount = (try? c.decode(Int.self, forKey: .trialTranscriptionCount)) ?? defaults.trialTranscriptionCount
    }
}

// MARK: - ConfigStore

@Observable
final class ConfigStore {
    static let shared = ConfigStore()

    private(set) var config: AppConfig

    private let configURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisprFlow", isDirectory: true)
        self.configURL = supportDir.appendingPathComponent("config.json")
        self.config = AppConfig()
        load()
    }

    // MARK: - Public

    func save(_ newConfig: AppConfig) {
        config = newConfig
        persist()
    }

    func update(_ mutate: (inout AppConfig) -> Void) {
        mutate(&config)
        persist()
    }

    // MARK: - Private

    private func load() {
        ensureDirectory()

        if let data = try? Data(contentsOf: configURL),
           let loaded = try? decoder.decode(AppConfig.self, from: data) {
            config = loaded
            logToFile("[ConfigStore] Loaded config from \(configURL.path)")
            return
        }

        // First launch or missing config — migrate from UserDefaults
        migrateFromUserDefaults()
        persist()
        logToFile("[ConfigStore] Created new config (migrated from UserDefaults)")
    }

    private func persist() {
        ensureDirectory()
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func migrateFromUserDefaults() {
        let ud = UserDefaults.standard
        var hasExistingData = false

        if let hotkey = ud.string(forKey: "hotkeyType") {
            config.hotkeyType = hotkey
            hasExistingData = true
        }

        if let outputMode = ud.string(forKey: "outputMode") {
            config.outputMode = outputMode
            hasExistingData = true
        }

        if let firstLaunch = ud.object(forKey: "whisprflow_first_launch") as? Double {
            config.trialFirstLaunch = firstLaunch
            hasExistingData = true
        }

        let trialCount = ud.integer(forKey: "whisprflow_trial_count")
        if trialCount > 0 {
            config.trialTranscriptionCount = trialCount
            hasExistingData = true
        }

        // If user has API key, they're definitely an existing user
        if KeychainHelper.hasAPIKey {
            hasExistingData = true
        }

        config.launchAtLogin = LaunchAtLogin.isEnabled

        // Existing users skip onboarding
        if hasExistingData {
            config.hasCompletedOnboarding = true
            logToFile("[ConfigStore] Existing user detected — skipping onboarding")
        }
    }
}
