import Foundation

/// Manages transcription requests to OpenAI API with single-request guard and timeout
final class TranscriptionManager {
    private var currentTask: Task<String, Error>?
    private let timeout: TimeInterval
    
    init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }
    
    enum TranscriptionError: Error, LocalizedError {
        case alreadyInProgress
        case timeout
        case networkError(String)
        case invalidAPIKey
        case noAPIKey
        case serverError(Int, String)
        case invalidResponse
        case emptyTranscription
        case fileNotFound
        
        var errorDescription: String? {
            switch self {
            case .alreadyInProgress: return "Transcription already in progress"
            case .timeout: return "Transcription timed out"
            case .networkError(let msg): return "Network error: \(msg)"
            case .invalidAPIKey: return "Invalid API key"
            case .noAPIKey: return "No API key configured"
            case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
            case .invalidResponse: return "Invalid response from server"
            case .emptyTranscription: return "No speech detected"
            case .fileNotFound: return "Audio file not found"
            }
        }
    }
    
    var isTranscribing: Bool {
        currentTask != nil
    }
    
    /// Transcribe audio file to text using OpenAI API
    func transcribe(audioURL: URL) async throws -> String {
        // Prevent concurrent transcriptions
        guard currentTask == nil else {
            throw TranscriptionError.alreadyInProgress
        }
        
        // Get API key
        guard let apiKey = KeychainHelper.getAPIKey(), !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound
        }
        
        let task = Task<String, Error> {
            try await withThrowingTaskGroup(of: String.self) { group in
                // API call task
                group.addTask {
                    try await self.callTranscriptionAPI(audioURL: audioURL, apiKey: apiKey)
                }
                
                // Timeout task
                group.addTask {
                    try await Task.sleep(for: .seconds(self.timeout))
                    throw TranscriptionError.timeout
                }
                
                // Return first result (success or timeout)
                guard let result = try await group.next() else {
                    throw TranscriptionError.invalidResponse
                }
                group.cancelAll()
                return result
            }
        }
        
        currentTask = task
        
        do {
            let result = try await task.value
            currentTask = nil
            return result
        } catch {
            currentTask = nil
            throw error
        }
    }
    
    private func callTranscriptionAPI(audioURL: URL, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("gpt-4o-transcribe\r\n".data(using: .utf8)!)
        
        // Add response_format field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)
        
        // Add language field (English)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        
        // Add file
        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        
        // Handle response
        switch httpResponse.statusCode {
        case 200:
            // For text format, response is just the transcribed text
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw TranscriptionError.invalidResponse
            }
            
            if text.isEmpty {
                throw TranscriptionError.emptyTranscription
            }
            
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
    
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}
