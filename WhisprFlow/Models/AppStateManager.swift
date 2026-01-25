import Foundation
import SwiftUI

/// Manages the app state machine with validated transitions.
/// This is the single source of truth for app state.
@Observable
final class AppStateManager {
    private(set) var state: AppState = .idle
    
    /// The audio file URL for the current or last recording (for retry)
    private(set) var currentRecordingURL: URL?
    
    /// The transcribed text from the last successful transcription
    private(set) var lastTranscription: String?
    
    /// Partial transcript for fast/realtime mode (updated as user speaks)
    var partialTranscript: String = ""
    
    /// Whether we're in fast/realtime mode
    var isFastMode: Bool = false
    
    // MARK: - State Queries
    
    var canStartRecording: Bool {
        state == .idle
    }
    
    var canStopRecording: Bool {
        state == .recording
    }
    
    var canCancelRecording: Bool {
        state == .recording
    }
    
    var canRetry: Bool {
        if case .error(let error) = state {
            return error.isRetryable && currentRecordingURL != nil
        }
        return false
    }
    
    var canDiscard: Bool {
        if case .error = state {
            return true
        }
        return false
    }
    
    // MARK: - State Transitions
    
    /// Attempt to start recording. Returns true if transition was valid.
    @discardableResult
    func startRecording() -> Bool {
        guard canStartRecording else { return false }
        state = .recording
        currentRecordingURL = nil
        lastTranscription = nil
        return true
    }
    
    /// Stop recording and begin transcription. Returns true if transition was valid.
    @discardableResult
    func stopRecording(audioURL: URL) -> Bool {
        guard canStopRecording else { return false }
        currentRecordingURL = audioURL
        state = .transcribing
        return true
    }
    
    /// Cancel the current recording. Returns true if transition was valid.
    @discardableResult
    func cancelRecording() -> Bool {
        guard canCancelRecording else { return false }
        state = .idle
        currentRecordingURL = nil
        return true
    }
    
    /// Mark transcription as successful
    func transcriptionSucceeded(text: String) {
        // Allow from transcribing (standard mode) or recording (fast mode)
        guard state == .transcribing || state == .recording else { return }
        lastTranscription = text
        state = .idle
    }
    
    /// Mark transcription as failed
    func transcriptionFailed(error: RecordingError) {
        guard state == .transcribing else { return }
        state = .error(error)
    }
    
    /// Retry transcription from error state
    @discardableResult
    func retry() -> Bool {
        guard canRetry else { return false }
        state = .transcribing
        return true
    }
    
    /// Discard failed recording and return to idle
    @discardableResult
    func discard() -> Bool {
        guard canDiscard else { return false }
        state = .idle
        currentRecordingURL = nil
        return true
    }
    
    /// Set error state directly (for permission errors, etc.)
    func setError(_ error: RecordingError) {
        state = .error(error)
    }
    
    /// Reset to idle state (for cleanup)
    func reset() {
        state = .idle
        currentRecordingURL = nil
        lastTranscription = nil
        partialTranscript = ""
        isFastMode = false
    }
    
    /// Update partial transcript (for fast mode)
    func updatePartialTranscript(_ text: String) {
        partialTranscript = text
    }
    
    /// Clear partial transcript
    func clearPartialTranscript() {
        partialTranscript = ""
    }
}
