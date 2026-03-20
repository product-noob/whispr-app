import Foundation

/// Common protocol for all transcription backends (cloud and local)
protocol TranscriptionBackend {
    /// Transcribe audio from a file URL and return the text
    func transcribe(audioURL: URL) async throws -> String

    /// Preload/warmup: load model into memory so first transcription is fast
    func preload() async throws

    /// Whether the backend is ready to transcribe
    var isReady: Bool { get }
}

/// Shared error type across all backends
enum TranscriptionError: Error, LocalizedError {
    case alreadyInProgress
    case timeout
    case networkError(String)
    case invalidAPIKey
    case noAPIKey
    case trialEnded
    case serverError(Int, String)
    case invalidResponse
    case emptyTranscription
    case fileNotFound
    case modelNotLoaded
    case modelDownloadFailed(String)
    case audioLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress: return "Transcription already in progress"
        case .timeout: return "Transcription timed out"
        case .networkError(let msg): return "Network error: \(msg)"
        case .invalidAPIKey: return "Invalid API key"
        case .noAPIKey: return "No API key configured"
        case .trialEnded: return "Trial ended — add your own API key"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .invalidResponse: return "Invalid response from server"
        case .emptyTranscription: return "No speech detected"
        case .fileNotFound: return "Audio file not found"
        case .modelNotLoaded: return "Transcription model not loaded"
        case .modelDownloadFailed(let msg): return "Model download failed: \(msg)"
        case .audioLoadFailed(let msg): return "Audio load failed: \(msg)"
        }
    }
}
