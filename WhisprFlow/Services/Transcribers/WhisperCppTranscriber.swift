#if canImport(SwiftWhisper)
import Foundation
import SwiftWhisper

// Retroactive Sendable conformances for SwiftWhisper types.
// Safe because all whisper operations are serialized on a single DispatchQueue.
extension Whisper: @retroactive @unchecked Sendable {}
extension WhisperParams: @retroactive @unchecked Sendable {}

/// whisper.cpp transcription backend using SwiftWhisper (CPU + Metal GPU).
/// All whisper operations are serialized to avoid thread-safety issues in the C layer.
final class WhisperCppTranscriber: TranscriptionBackend, @unchecked Sendable {
    private var whisper: Whisper?
    private let modelPath: URL
    private let serialQueue = DispatchQueue(label: "com.whisprflow.whisper", qos: .userInitiated)

    var isReady: Bool { whisper != nil }

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    func preload() async throws {
        guard whisper == nil else { return }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: modelPath.path)[.size] as? Int) ?? 0
        if fileSize < 10_000_000 {
            throw TranscriptionError.modelDownloadFailed("Model file too small (\(fileSize) bytes), likely corrupted")
        }

        logToFile("[WhisperCppTranscriber] Loading model: \(modelPath.lastPathComponent) (\(fileSize / 1_000_000)MB)...")

        let params = WhisperParams(strategy: .greedy)
        params.language = .english
        params.n_threads = Int32(max(4, ProcessInfo.processInfo.activeProcessorCount - 2))
        params.no_context = true
        params.single_segment = true
        params.print_progress = false
        params.print_timestamps = false
        params.suppress_blank = true

        let modelURL = self.modelPath
        let queue = self.serialQueue
        let loadedWhisper = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Whisper, Error>) in
            queue.async {
                let w = Whisper(fromFileURL: modelURL, withParams: params)
                cont.resume(returning: w)
            }
        }

        whisper = loadedWhisper
        logToFile("[WhisperCppTranscriber] Model ready (threads: \(params.n_threads))")
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let whisper else {
            throw TranscriptionError.modelNotLoaded
        }

        let samples = try loadAudioSamples(from: audioURL)

        if samples.count < 16000 {
            throw TranscriptionError.emptyTranscription
        }

        logToFile("[WhisperCppTranscriber] Transcribing \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000.0))s)...")

        let queue = self.serialQueue
        let segments: [Segment] = try await withCheckedThrowingContinuation { cont in
            queue.async {
                whisper.transcribe(audioFrames: samples) { result in
                    switch result {
                    case .success(let segs):
                        cont.resume(returning: segs)
                    case .failure(let error):
                        cont.resume(throwing: error)
                    }
                }
            }
        }

        let text = segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        logToFile("[WhisperCppTranscriber] Result: \(text.prefix(80))...")

        if text.isEmpty { throw TranscriptionError.emptyTranscription }
        return text
    }

    func shutdown() {
        whisper = nil
    }

    // MARK: - Audio Loading

    private func loadAudioSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else {
            throw TranscriptionError.audioLoadFailed("WAV file too small (\(data.count) bytes)")
        }

        let pcmData = data.dropFirst(44)
        let sampleCount = pcmData.count / 2
        var floats = [Float](repeating: 0, count: sampleCount)

        pcmData.withUnsafeBytes { raw in
            let int16Buffer = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floats[i] = Float(int16Buffer[i]) / 32767.0
            }
        }

        return floats
    }
}
#endif
