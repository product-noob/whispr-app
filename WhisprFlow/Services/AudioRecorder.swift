import AVFoundation
import Foundation

/// Handles audio recording using AVAudioEngine
/// Supports two modes:
/// - Standard: Records to file at 16kHz for batch upload
/// - Streaming: Streams PCM chunks at 24kHz for realtime API
final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var isStreamingMode = false
    private var currentRecordingURL: URL?
    
    // Audio format settings
    private let standardSampleRate: Double = 16000   // For standard file recording
    private let streamingSampleRate: Double = 24000  // For realtime API (required)
    private let channels: AVAudioChannelCount = 1
    
    // Streaming callback - receives PCM16 data at 24kHz
    var onAudioChunk: ((Data) -> Void)?
    
    // For backward compatibility
    private var sampleRate: Double { standardSampleRate }
    
    enum RecorderError: Error, LocalizedError {
        case permissionDenied
        case engineSetupFailed
        case recordingInProgress
        case notRecording
        case fileCreationFailed
        case compressionFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Microphone permission denied"
            case .engineSetupFailed: return "Failed to setup audio engine"
            case .recordingInProgress: return "Recording already in progress"
            case .notRecording: return "No recording in progress"
            case .fileCreationFailed: return "Failed to create audio file"
            case .compressionFailed(let reason): return "Audio compression failed: \(reason)"
            }
        }
    }
    
    // MARK: - Permission
    
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    var hasPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    // MARK: - Recording
    
    func startRecording() throws -> URL {
        guard !isRecording else {
            throw RecorderError.recordingInProgress
        }
        
        guard hasPermission else {
            throw RecorderError.permissionDenied
        }
        
        // Create recording URL
        let url = createRecordingURL()
        
        // Setup audio engine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        // Get the native format and create a converter format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create output format (16kHz mono for optimal Whisper performance)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw RecorderError.engineSetupFailed
        }
        
        // Create audio file
        guard let file = try? AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        ) else {
            throw RecorderError.fileCreationFailed
        }
        
        // Create format converter if needed
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            if let converter = converter {
                // Convert to output format
                let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate)
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else { return }
                
                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                
                converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
                
                if error == nil {
                    try? file.write(from: convertedBuffer)
                }
            } else {
                // Write directly if formats match
                try? file.write(from: buffer)
            }
        }
        
        // Start engine
        engine.prepare()
        try engine.start()
        
        self.audioEngine = engine
        self.audioFile = file
        self.currentRecordingURL = url
        self.isRecording = true
        
        return url
    }
    
    func stopRecording() throws -> URL {
        guard isRecording, let url = currentRecordingURL else {
            throw RecorderError.notRecording
        }
        
        // Stop and cleanup
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false
        
        let finalURL = url
        currentRecordingURL = nil
        
        return finalURL
    }
    
    func cancelRecording() {
        guard isRecording else { return }
        
        let url = currentRecordingURL
        
        // Stop and cleanup
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false
        isStreamingMode = false
        currentRecordingURL = nil
        
        // Delete the file
        if let url = url {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Streaming Recording (for Realtime API)
    
    /// Start streaming recording at 24kHz for realtime transcription
    /// Audio chunks are sent via onAudioChunk callback
    func startStreamingRecording() throws {
        guard !isRecording else {
            throw RecorderError.recordingInProgress
        }
        
        guard hasPermission else {
            throw RecorderError.permissionDenied
        }
        
        logToFile("[AudioRecorder] Starting streaming recording at 24kHz...")
        
        // Setup audio engine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        // Get the native format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Target format: 24kHz mono Float32 for conversion
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: streamingSampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw RecorderError.engineSetupFailed
        }
        
        // Create converter
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        
        // Chunk size: ~40ms of audio at 24kHz = 960 samples
        // Each sample is 2 bytes (16-bit), so 1920 bytes per chunk
        let chunkSamples = 960
        var audioBuffer = Data()
        
        // Install tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, let converter = converter else { return }
            
            // Convert to target format
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * self.streamingSampleRate / inputFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            guard error == nil,
                  let floatChannelData = convertedBuffer.floatChannelData else { return }
            
            // Convert Float32 to Int16 PCM
            let frameLength = Int(convertedBuffer.frameLength)
            var pcmData = Data(capacity: frameLength * 2)
            
            for i in 0..<frameLength {
                let floatSample = floatChannelData[0][i]
                // Clamp and convert to Int16
                let clampedSample = max(-1.0, min(1.0, floatSample))
                let int16Sample = Int16(clampedSample * 32767)
                // Little-endian
                var sample = int16Sample.littleEndian
                pcmData.append(Data(bytes: &sample, count: 2))
            }
            
            // Accumulate in buffer
            audioBuffer.append(pcmData)
            
            // Send chunks when we have enough data
            while audioBuffer.count >= chunkSamples * 2 {
                let chunk = audioBuffer.prefix(chunkSamples * 2)
                audioBuffer.removeFirst(chunkSamples * 2)
                
                // Call callback on main thread
                let chunkData = Data(chunk)
                DispatchQueue.main.async {
                    self.onAudioChunk?(chunkData)
                }
            }
        }
        
        // Start engine
        engine.prepare()
        try engine.start()
        
        self.audioEngine = engine
        self.isRecording = true
        self.isStreamingMode = true
        
        logToFile("[AudioRecorder] Streaming recording started")
    }
    
    /// Stop streaming recording
    func stopStreamingRecording() {
        guard isRecording, isStreamingMode else { return }
        
        logToFile("[AudioRecorder] Stopping streaming recording...")
        
        // Stop and cleanup
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        isStreamingMode = false
        
        logToFile("[AudioRecorder] Streaming recording stopped")
    }
    
    /// Check if currently in streaming mode
    var isStreaming: Bool {
        return isRecording && isStreamingMode
    }
    
    // MARK: - Audio Compression
    
    /// Compress WAV to M4A (AAC) for faster upload
    /// Returns the compressed file URL and deletes the original WAV
    func compressToM4A(wavURL: URL) async throws -> URL {
        let outputURL = wavURL.deletingPathExtension().appendingPathExtension("m4a")
        
        // Load the WAV file as an asset
        let asset = AVURLAsset(url: wavURL)
        
        // Check if asset is exportable
        let isExportable = try await asset.load(.isExportable)
        guard isExportable else {
            throw RecorderError.compressionFailed("Audio file is not exportable")
        }
        
        // Create export session with AAC preset
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw RecorderError.compressionFailed("Could not create export session")
        }
        
        // Configure export
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)
        
        // Export using newer async API
        do {
            try await exportSession.export(to: outputURL, as: .m4a)
        } catch {
            throw RecorderError.compressionFailed(error.localizedDescription)
        }
        
        // Verify output file exists
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw RecorderError.compressionFailed("Output file was not created")
        }
        
        // Log compression result
        let wavSize = getFileSize(at: wavURL)
        let m4aSize = getFileSize(at: outputURL)
        if wavSize > 0 && m4aSize > 0 {
            let ratio = Double(wavSize) / Double(m4aSize)
            logToFile("[AudioRecorder] Compressed \(wavSize) bytes -> \(m4aSize) bytes (ratio: \(String(format: "%.1f", ratio))x)")
        }
        
        // Delete original WAV to save space
        try? FileManager.default.removeItem(at: wavURL)
        
        return outputURL
    }
    
    /// Get file size in bytes
    func getFileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }
    
    // MARK: - Helpers
    
    private func createRecordingURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("WhisprFlow/recordings", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        
        let filename = "\(UUID().uuidString)_\(Int(Date().timeIntervalSince1970)).wav"
        return recordingsPath.appendingPathComponent(filename)
    }
}
