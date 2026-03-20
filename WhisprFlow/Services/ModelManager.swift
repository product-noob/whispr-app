import Foundation

/// Manages local model downloads, storage, and availability checks
@Observable
final class ModelManager: @unchecked Sendable {
    static let shared = ModelManager()

    var downloadProgress: Double = 0
    var isDownloading = false
    var downloadError: String?
    private(set) var downloadedModels: Set<TranscriptionModel> = []

    private let modelsDir: URL
    private var currentDownloadTask: Task<Void, Error>?

    private static let whisperURLs: [String: String] = [
        "ggml-small.en-q5_1": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin",
        "ggml-large-v3-turbo-q5_0": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin",
    ]

    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        modelsDir = supportDir.appendingPathComponent("WhisprFlow/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        refreshDownloadedModels()
    }

    // MARK: - Public

    func isModelAvailable(_ model: TranscriptionModel) -> Bool {
        switch model {
        case .openAI:
            return true
        case .parakeetV3:
            return isFluidAudioModelAvailable()
        case .whisperSmall, .whisperLargeTurbo:
            guard let name = model.whisperModelName else { return false }
            return FileManager.default.fileExists(atPath: whisperModelPath(name).path)
        }
    }

    func downloadModel(_ model: TranscriptionModel, progress: ((Double, String?) -> Void)? = nil) async throws {
        guard !isDownloading else { return }

        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
            downloadError = nil
        }

        defer {
            Task { @MainActor in
                isDownloading = false
                refreshDownloadedModels()
            }
        }

        switch model {
        case .openAI:
            return // Nothing to download

        case .parakeetV3:
            // FluidAudio handles its own download via AsrModels.downloadAndLoad
            // This is triggered during preload in FluidAudioTranscriber
            logToFile("[ModelManager] Parakeet download is handled by FluidAudio during preload")

        case .whisperSmall, .whisperLargeTurbo:
            guard let name = model.whisperModelName else { return }
            try await downloadWhisperModel(name: name, progress: progress)
        }
    }

    func deleteModel(_ model: TranscriptionModel) throws {
        switch model {
        case .openAI:
            return
        case .parakeetV3:
            // FluidAudio manages its own cache — don't delete
            logToFile("[ModelManager] Parakeet model deletion not supported (managed by FluidAudio)")
        case .whisperSmall, .whisperLargeTurbo:
            guard let name = model.whisperModelName else { return }
            let path = whisperModelPath(name)
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
                logToFile("[ModelManager] Deleted model: \(name)")
                refreshDownloadedModels()
            }
        }
    }

    func modelPath(_ model: TranscriptionModel) -> URL? {
        switch model {
        case .openAI, .parakeetV3:
            return nil
        case .whisperSmall, .whisperLargeTurbo:
            guard let name = model.whisperModelName else { return nil }
            let path = whisperModelPath(name)
            return FileManager.default.fileExists(atPath: path.path) ? path : nil
        }
    }

    // MARK: - Private

    private func whisperModelPath(_ name: String) -> URL {
        let filename = name.hasSuffix(".bin") ? name : "\(name).bin"
        return modelsDir.appendingPathComponent(filename)
    }

    private func isFluidAudioModelAvailable() -> Bool {
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FluidAudio/Models")
        guard let contents = try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) else {
            return false
        }
        return contents.contains { $0.lastPathComponent.contains("parakeet") && $0.lastPathComponent.contains("v3") }
    }

    private func refreshDownloadedModels() {
        var models = Set<TranscriptionModel>()
        models.insert(.openAI)
        for model in TranscriptionModel.allCases where model != .openAI {
            if isModelAvailable(model) {
                models.insert(model)
            }
        }
        downloadedModels = models
    }

    private func downloadWhisperModel(name: String, progress: ((Double, String?) -> Void)?) async throws {
        let localPath = whisperModelPath(name)

        if FileManager.default.fileExists(atPath: localPath.path) {
            logToFile("[ModelManager] Model already exists: \(name)")
            return
        }

        guard let urlString = Self.whisperURLs[name],
              let url = URL(string: urlString) else {
            throw ModelDownloadError.unknownModel(name)
        }

        logToFile("[ModelManager] Downloading \(name) from HuggingFace...")

        let delegate = DownloadProgressDelegate { [weak self] fraction in
            DispatchQueue.main.async {
                self?.downloadProgress = fraction
            }
            progress?(fraction, "Downloading \(name)...")
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, _) = try await session.download(from: url)
        try FileManager.default.moveItem(at: tempURL, to: localPath)

        // Validate file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localPath.path)[.size] as? Int) ?? 0
        if fileSize < 10_000_000 {
            try? FileManager.default.removeItem(at: localPath)
            throw ModelDownloadError.corruptedDownload(name)
        }

        logToFile("[ModelManager] Download complete: \(name) (\(fileSize / 1_000_000)MB)")
    }

    enum ModelDownloadError: Error, LocalizedError {
        case unknownModel(String)
        case corruptedDownload(String)

        var errorDescription: String? {
            switch self {
            case .unknownModel(let name): return "Unknown model: \(name)"
            case .corruptedDownload(let name): return "Downloaded file for \(name) appears corrupted. Try again."
            }
        }
    }
}

// MARK: - Download Progress Delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Handled by the async download call
    }
}
