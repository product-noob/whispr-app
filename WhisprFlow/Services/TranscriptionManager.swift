import Foundation

/// Routes transcription requests to the appropriate backend (cloud or local)
final class TranscriptionManager {
    private var currentBackend: TranscriptionBackend?
    private var currentModel: TranscriptionModel?
    private var currentTask: Task<String, Error>?

    init() {}

    var isTranscribing: Bool {
        currentTask != nil
    }

    /// Set the active transcription model and preload its backend
    func setModel(_ model: TranscriptionModel) async throws {
        // Skip if already loaded
        if currentModel == model, currentBackend?.isReady == true { return }

        logToFile("[TranscriptionManager] Setting model: \(model.displayName)")

        switch model {
        case .openAI:
            currentBackend = OpenAITranscriber()

        case .parakeetV3:
            #if canImport(FluidAudio)
            let transcriber = FluidAudioTranscriber()
            try await transcriber.preload()
            currentBackend = transcriber
            #else
            logToFile("[TranscriptionManager] FluidAudio not available — falling back to OpenAI")
            currentBackend = OpenAITranscriber()
            #endif

        case .whisperSmall, .whisperLargeTurbo:
            #if canImport(SwiftWhisper)
            guard let path = ModelManager.shared.modelPath(model) else {
                throw TranscriptionError.modelNotLoaded
            }
            let transcriber = WhisperCppTranscriber(modelPath: path)
            try await transcriber.preload()
            currentBackend = transcriber
            #else
            logToFile("[TranscriptionManager] SwiftWhisper not available — falling back to OpenAI")
            currentBackend = OpenAITranscriber()
            #endif
        }

        currentModel = model
        logToFile("[TranscriptionManager] Model ready: \(model.displayName)")
    }

    /// Transcribe audio file using the current backend
    func transcribe(audioURL: URL) async throws -> String {
        guard currentTask == nil else {
            throw TranscriptionError.alreadyInProgress
        }

        // Auto-initialize if needed
        if currentBackend == nil {
            let model = TranscriptionModel(rawValue: ConfigStore.shared.config.selectedModel) ?? .openAI
            try await setModel(model)
        }

        guard let backend = currentBackend else {
            throw TranscriptionError.modelNotLoaded
        }

        let task = Task<String, Error> {
            try await backend.transcribe(audioURL: audioURL)
        }
        currentTask = task

        do {
            let result = try await task.value
            currentTask = nil

            // Record for trial tracking (OpenAI only)
            if currentModel == .openAI {
                TrialTracker.shared.recordTranscription()
            }

            return result
        } catch {
            currentTask = nil
            throw error
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}
