import AVFoundation
import Foundation

/// Handles audio recording using AVAudioEngine
final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var currentRecordingURL: URL?
    
    // Audio format settings optimized for speech recognition
    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1
    
    enum RecorderError: Error, LocalizedError {
        case permissionDenied
        case engineSetupFailed
        case recordingInProgress
        case notRecording
        case fileCreationFailed
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Microphone permission denied"
            case .engineSetupFailed: return "Failed to setup audio engine"
            case .recordingInProgress: return "Recording already in progress"
            case .notRecording: return "No recording in progress"
            case .fileCreationFailed: return "Failed to create audio file"
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
        currentRecordingURL = nil
        
        // Delete the file
        if let url = url {
            try? FileManager.default.removeItem(at: url)
        }
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
