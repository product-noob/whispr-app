import Foundation

enum TranscriptionModel: String, Codable, CaseIterable, Identifiable {
    case openAI = "openai"
    case parakeetV3 = "parakeet-v3"
    case whisperSmall = "whisper-small"
    case whisperLargeTurbo = "whisper-large-turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI (Cloud)"
        case .parakeetV3: return "Parakeet v3"
        case .whisperSmall: return "Whisper Small"
        case .whisperLargeTurbo: return "Whisper Large Turbo"
        }
    }

    var description: String {
        switch self {
        case .openAI: return "Best accuracy. Requires API key and internet."
        case .parakeetV3: return "Fast, runs on Apple Neural Engine. Recommended."
        case .whisperSmall: return "Small and fast. English-optimized, quantized."
        case .whisperLargeTurbo: return "Highest local accuracy. Multilingual, quantized."
        }
    }

    var isLocal: Bool { self != .openAI }

    var requiresAPIKey: Bool { self == .openAI }

    var downloadSizeMB: Int {
        switch self {
        case .openAI: return 0
        case .parakeetV3: return 250
        case .whisperSmall: return 190
        case .whisperLargeTurbo: return 600
        }
    }

    var isRecommended: Bool { self == .parakeetV3 }

    /// The ggml model filename for whisper models (used by ModelManager)
    var whisperModelName: String? {
        switch self {
        case .whisperSmall: return "ggml-small.en-q5_1"
        case .whisperLargeTurbo: return "ggml-large-v3-turbo-q5_0"
        default: return nil
        }
    }
}
