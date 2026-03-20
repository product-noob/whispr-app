import Foundation

/// OpenAI Whisper API transcription backend (cloud)
final class OpenAITranscriber: TranscriptionBackend {
    private let baseTimeout: TimeInterval = 45
    private let maxTimeout: TimeInterval = 180
    private let timeoutPerMB: TimeInterval = 15

    var isReady: Bool { true }

    func preload() async throws {
        // No preloading needed for cloud API
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let apiKey = TrialTracker.shared.getAPIKey(), !apiKey.isEmpty else {
            if TrialTracker.shared.trialEnded && !KeychainHelper.hasAPIKey {
                throw TranscriptionError.trialEnded
            }
            throw TranscriptionError.noAPIKey
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0
        let timeout = calculateTimeout(for: fileSize)

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.callTranscriptionAPI(audioURL: audioURL, apiKey: apiKey)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TranscriptionError.timeout
            }
            guard let result = try await group.next() else {
                throw TranscriptionError.invalidResponse
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Private

    private func calculateTimeout(for fileSize: Int64) -> TimeInterval {
        let mbSize = Double(fileSize) / (1024 * 1024)
        let calculated = baseTimeout + (mbSize * timeoutPerMB)
        return min(maxTimeout, max(baseTimeout, calculated))
    }

    private func callTranscriptionAPI(audioURL: URL, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("gpt-4o-transcribe\r\n".data(using: .utf8)!)

        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)

        // Language
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)

        // Prompt — guides formatting and style
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("Use proper formatting: bullet points, numbered lists, URLs, and paragraph breaks where appropriate. Preserve technical terms, acronyms, and proper nouns accurately.\r\n".data(using: .utf8)!)

        // Audio file
        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent
        let ext = audioURL.pathExtension.lowercased()
        let contentType: String
        switch ext {
        case "m4a": contentType = "audio/mp4"
        case "mp3": contentType = "audio/mpeg"
        case "wav": contentType = "audio/wav"
        default: contentType = "audio/\(ext)"
        }

        logToFile("[OpenAITranscriber] Uploading \(filename) (\(audioData.count) bytes) as \(contentType)")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw TranscriptionError.invalidResponse
            }
            if text.isEmpty { throw TranscriptionError.emptyTranscription }
            return text
        case 401:
            throw TranscriptionError.invalidAPIKey
        case 429:
            throw TranscriptionError.serverError(429, "Rate limit exceeded")
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.serverError(httpResponse.statusCode, errorMessage)
        }
    }
}
