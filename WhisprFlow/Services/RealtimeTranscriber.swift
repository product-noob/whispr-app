import Foundation
import AVFoundation

/// WebSocket-based realtime transcription using OpenAI Realtime API
/// Streams audio chunks and receives incremental transcription deltas
final class RealtimeTranscriber: NSObject {
    
    // MARK: - Types
    
    enum RealtimeError: Error, LocalizedError {
        case notConnected
        case connectionFailed(String)
        case noAPIKey
        case invalidResponse
        case sessionError(String)
        
        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to realtime API"
            case .connectionFailed(let reason): return "Connection failed: \(reason)"
            case .noAPIKey: return "No API key configured"
            case .invalidResponse: return "Invalid response from server"
            case .sessionError(let msg): return "Session error: \(msg)"
            }
        }
    }
    
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case transcribing
    }
    
    // MARK: - Properties
    
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private(set) var state: ConnectionState = .disconnected
    
    // Accumulated transcript
    private var currentTranscript = ""
    private var partialTranscript = ""
    
    // Callbacks
    var onPartialTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onStateChange: ((ConnectionState) -> Void)?
    
    // Constants
    private let realtimeURL = "wss://api.openai.com/v1/realtime?intent=transcription"
    private let targetSampleRate: Double = 24000  // Realtime API requires 24kHz
    
    // MARK: - Connection
    
    /// Connect to the Realtime API
    func connect() async throws {
        guard let apiKey = KeychainHelper.getAPIKey(), !apiKey.isEmpty else {
            throw RealtimeError.noAPIKey
        }
        
        guard state == .disconnected else {
            logToFile("[RealtimeTranscriber] Already connected or connecting")
            return
        }
        
        updateState(.connecting)
        logToFile("[RealtimeTranscriber] Connecting to Realtime API...")
        
        // Create URL request with auth headers
        guard let url = URL(string: realtimeURL) else {
            throw RealtimeError.connectionFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        
        // Create WebSocket task
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        urlSession = session
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()
        
        // Wait for connection to establish
        try await Task.sleep(for: .milliseconds(500))
        
        // Configure transcription session
        try await sendSessionConfig()
        
        updateState(.connected)
        logToFile("[RealtimeTranscriber] Connected successfully")
        
        // Start receiving messages
        startReceiving()
    }
    
    /// Disconnect from the Realtime API
    func disconnect() {
        logToFile("[RealtimeTranscriber] Disconnecting...")
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        currentTranscript = ""
        partialTranscript = ""
        updateState(.disconnected)
    }
    
    // MARK: - Audio Streaming
    
    /// Send audio chunk to the API
    /// Audio must be PCM 16-bit at 24kHz
    func sendAudioChunk(_ pcmData: Data) {
        guard state == .connected || state == .transcribing else {
            logToFile("[RealtimeTranscriber] Cannot send audio - not connected (state: \(state))")
            return
        }
        
        if state == .connected {
            updateState(.transcribing)
        }
        
        let base64Audio = pcmData.base64EncodedString()
        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Audio
        ]
        
        sendJSON(message)
    }
    
    /// Signal end of audio input by committing the buffer
    func endAudio() {
        logToFile("[RealtimeTranscriber] Committing audio buffer...")
        let message: [String: Any] = ["type": "input_audio_buffer.commit"]
        sendJSON(message)
    }
    
    /// Get the current accumulated transcript
    func getCurrentTranscript() -> String {
        return currentTranscript + partialTranscript
    }
    
    /// Reset transcript accumulator
    func resetTranscript() {
        currentTranscript = ""
        partialTranscript = ""
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ newState: ConnectionState) {
        state = newState
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onStateChange?(newState)
        }
    }
    
    private func sendSessionConfig() async throws {
        let config: [String: Any] = [
            "type": "transcription_session.update",
            "session": [
                "input_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "gpt-4o-transcribe",
                    "language": "en"
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 500
                ]
            ]
        ]
        
        sendJSON(config)
        logToFile("[RealtimeTranscriber] Session config sent")
    }
    
    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: data, encoding: .utf8) else {
            logToFile("[RealtimeTranscriber] Failed to serialize JSON")
            return
        }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        webSocket?.send(message) { [weak self] error in
            if let error = error {
                logToFile("[RealtimeTranscriber] Send error: \(error.localizedDescription)")
                self?.onError?(error)
            }
        }
    }
    
    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.startReceiving()
                
            case .failure(let error):
                logToFile("[RealtimeTranscriber] Receive error: \(error.localizedDescription)")
                if self.state != .disconnected {
                    self.onError?(error)
                    self.updateState(.disconnected)
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleJSONMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleJSONMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func handleJSONMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "conversation.item.input_audio_transcription.delta":
            // Incremental transcript update
            if let delta = json["delta"] as? String {
                partialTranscript += delta
                let fullTranscript = currentTranscript + partialTranscript
                DispatchQueue.main.async { [weak self] in
                    self?.onPartialTranscript?(fullTranscript)
                }
            }
            
        case "conversation.item.input_audio_transcription.completed":
            // Turn completed
            if let transcript = json["transcript"] as? String {
                currentTranscript += transcript + " "
                partialTranscript = ""
                logToFile("[RealtimeTranscriber] Turn completed: \(transcript.prefix(50))...")
            }
            
        case "input_audio_buffer.committed":
            // Audio buffer was committed (VAD detected end of speech)
            logToFile("[RealtimeTranscriber] Audio buffer committed")
            
        case "error":
            // Handle errors
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                logToFile("[RealtimeTranscriber] Server error: \(message)")
                DispatchQueue.main.async { [weak self] in
                    self?.onError?(RealtimeError.sessionError(message))
                }
            }
            
        case "session.created", "session.updated", "transcription_session.updated":
            logToFile("[RealtimeTranscriber] Session event: \(type)")
            
        default:
            // Log unknown message types for debugging
            logToFile("[RealtimeTranscriber] Unknown message type: \(type)")
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension RealtimeTranscriber: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logToFile("[RealtimeTranscriber] WebSocket opened")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        logToFile("[RealtimeTranscriber] WebSocket closed with code: \(closeCode.rawValue)")
        updateState(.disconnected)
    }
}
