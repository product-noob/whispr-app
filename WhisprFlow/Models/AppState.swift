import Foundation

/// The four possible states of the WhisprFlow app.
/// All UI and logic must respect these states and their valid transitions.
enum AppState: Equatable {
    case idle
    case recording
    case transcribing
    case error(RecordingError)
    
    var isIdle: Bool { self == .idle }
    var isRecording: Bool { self == .recording }
    var isTranscribing: Bool { self == .transcribing }
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

/// Errors that can occur during the recording/transcription flow
enum RecordingError: Equatable, LocalizedError {
    case microphonePermissionDenied
    case microphoneUnavailable
    case recordingFailed(String)
    case transcriptionTimeout
    case transcriptionFailed(String)
    case networkError(String)
    case invalidAPIKey
    case noAPIKey
    case emptyTranscription
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access denied"
        case .microphoneUnavailable:
            return "Microphone unavailable"
        case .recordingFailed(let message):
            return "Recording failed: \(message)"
        case .transcriptionTimeout:
            return "Transcription timed out"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidAPIKey:
            return "Invalid API key"
        case .noAPIKey:
            return "No API key configured"
        case .emptyTranscription:
            return "No speech detected"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .microphonePermissionDenied, .microphoneUnavailable, .noAPIKey, .invalidAPIKey:
            return false
        case .recordingFailed, .transcriptionTimeout, .transcriptionFailed, .networkError, .emptyTranscription:
            return true
        }
    }
}
