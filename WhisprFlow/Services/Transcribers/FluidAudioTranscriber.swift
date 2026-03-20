#if canImport(FluidAudio)
import FluidAudio
import Foundation

/// Parakeet v3 transcription backend using FluidAudio's CoreML model on Apple Neural Engine
final class FluidAudioTranscriber: TranscriptionBackend {
    private var asrManager: AsrManager?

    var isReady: Bool { asrManager != nil }

    func preload() async throws {
        guard asrManager == nil else { return }
        logToFile("[FluidAudioTranscriber] Downloading/loading Parakeet v3 models...")
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        asrManager = manager
        logToFile("[FluidAudioTranscriber] Models ready")
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let asrManager else {
            throw TranscriptionError.modelNotLoaded
        }
        let result = try await asrManager.transcribe(audioURL)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw TranscriptionError.emptyTranscription }
        return text
    }

    func shutdown() {
        asrManager = nil
    }
}
#endif
