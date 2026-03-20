import AVFoundation
import Foundation

/// Handles audio recording using AVAudioEngine
final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var currentRecordingURL: URL?

    /// Current audio power level (0.0 to 1.0), smoothed. Updated during recording.
    private(set) var currentPowerLevel: Float = 0

    // Audio format settings
    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1
    
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
        
        // Install tap on input node (larger buffer = fewer callbacks = better performance)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            if let converter = converter {
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
                try? file.write(from: buffer)
            }

            // Compute RMS power level for amplitude visualization
            if let channelData = buffer.floatChannelData?[0] {
                let frames = UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength))
                let rms = sqrt(frames.reduce(0) { $0 + $1 * $1 } / Float(frames.count))
                let dB = 20 * log10(max(rms, 1e-7))
                let normalized = max(0, min(1, (dB + 40) / 35))
                DispatchQueue.main.async {
                    self.currentPowerLevel = self.currentPowerLevel * 0.25 + normalized * 0.75
                }
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
    
    func stopRecording() async throws -> URL {
        guard isRecording, let url = currentRecordingURL else {
            throw RecorderError.notRecording
        }
        
        // Add small delay to allow final audio buffers to flush
        // This prevents the last few spoken words from being cut off
        try await Task.sleep(for: .milliseconds(150))
        
        // Stop and cleanup
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false
        currentPowerLevel = 0

        let finalURL = url
        currentRecordingURL = nil
        
        logToFile("[AudioRecorder] Recording stopped with flush delay, file: \(finalURL.lastPathComponent)")
        
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
        currentPowerLevel = 0
        
        // Delete the file
        if let url = url {
            try? FileManager.default.removeItem(at: url)
        }
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
    
    /// Check if file should be compressed (skip for small files under 500KB)
    /// Small WAV files upload quickly enough without compression overhead
    func shouldCompress(fileURL: URL) -> Bool {
        let size = getFileSize(at: fileURL)
        let threshold: Int64 = 500 * 1024 // 500KB
        let shouldCompress = size > threshold
        logToFile("[AudioRecorder] File size: \(size) bytes, should compress: \(shouldCompress)")
        return shouldCompress
    }
    
    // MARK: - F5: Silence Trimming

    /// Trims leading and trailing silence from a WAV file.
    /// Returns the trimmed file URL, or nil if the entire file is silence.
    func trimSilence(wavURL: URL) -> URL? {
        guard let data = try? Data(contentsOf: wavURL) else { return nil }

        // WAV header is 44 bytes; samples are 16-bit signed LE mono at 16kHz
        let headerSize = 44
        guard data.count > headerSize else { return nil }

        let sampleData = data.subdata(in: headerSize..<data.count)
        let sampleCount = sampleData.count / 2
        guard sampleCount > 0 else { return nil }

        // Read samples as Int16
        let samples: [Int16] = sampleData.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: Int16.self)
            return Array(buffer)
        }

        // Calculate RMS in 50ms windows (800 samples at 16kHz)
        let windowSize = 800
        let silenceThreshold: Float = 0.01
        let windowCount = sampleCount / windowSize

        guard windowCount > 0 else {
            // Very short file — keep it all
            return wavURL
        }

        // Find first non-silent window from start
        var firstActiveWindow = windowCount // default: all silent
        for i in 0..<windowCount {
            let start = i * windowSize
            let end = min(start + windowSize, sampleCount)
            let rms = rmsForRange(samples: samples, start: start, end: end)
            if rms >= silenceThreshold {
                firstActiveWindow = i
                break
            }
        }

        // If entire file is silence, return nil
        if firstActiveWindow >= windowCount {
            logToFile("[AudioRecorder] Entire file is silence, skipping transcription")
            return nil
        }

        // Find first non-silent window from end
        var lastActiveWindow = firstActiveWindow
        for i in stride(from: windowCount - 1, through: 0, by: -1) {
            let start = i * windowSize
            let end = min(start + windowSize, sampleCount)
            let rms = rmsForRange(samples: samples, start: start, end: end)
            if rms >= silenceThreshold {
                lastActiveWindow = i
                break
            }
        }

        // Add 100ms padding (1600 samples) on both sides
        let paddingSamples = 1600
        let trimStart = max(0, firstActiveWindow * windowSize - paddingSamples)
        let trimEnd = min(sampleCount, (lastActiveWindow + 1) * windowSize + paddingSamples)

        // If we're not trimming much, skip rewrite
        if trimStart == 0 && trimEnd >= sampleCount - windowSize {
            return wavURL
        }

        // Write trimmed WAV
        let trimmedSamples = Array(samples[trimStart..<trimEnd])
        let trimmedURL = wavURL.deletingLastPathComponent()
            .appendingPathComponent("trimmed_\(wavURL.lastPathComponent)")

        if writeWAV(samples: trimmedSamples, to: trimmedURL) {
            try? FileManager.default.removeItem(at: wavURL)
            logToFile("[AudioRecorder] Trimmed silence: \(sampleCount) → \(trimmedSamples.count) samples")
            return trimmedURL
        }

        return wavURL
    }

    // MARK: - F7: Audio Level Normalization

    /// Normalizes quiet audio to a target peak of 0.9. Only amplifies, never attenuates.
    func normalizeAudio(wavURL: URL) -> URL {
        guard let data = try? Data(contentsOf: wavURL) else { return wavURL }

        let headerSize = 44
        guard data.count > headerSize else { return wavURL }

        let sampleData = data.subdata(in: headerSize..<data.count)
        let sampleCount = sampleData.count / 2
        guard sampleCount > 0 else { return wavURL }

        var samples: [Int16] = sampleData.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: Int16.self)
            return Array(buffer)
        }

        // Find peak absolute value
        let peak = samples.map { abs(Int32($0)) }.max() ?? 0
        guard peak > 0 else { return wavURL }

        let peakFloat = Float(peak) / Float(Int16.max)
        let targetPeak: Float = 0.9
        let gain = targetPeak / peakFloat

        // Only amplify (gain > 1.0), never attenuate
        guard gain > 1.0 else { return wavURL }

        // Apply gain
        for i in 0..<samples.count {
            let amplified = Float(samples[i]) * gain
            samples[i] = Int16(max(Float(Int16.min), min(Float(Int16.max), amplified)))
        }

        let normalizedURL = wavURL.deletingLastPathComponent()
            .appendingPathComponent("norm_\(wavURL.lastPathComponent)")

        if writeWAV(samples: samples, to: normalizedURL) {
            try? FileManager.default.removeItem(at: wavURL)
            logToFile("[AudioRecorder] Normalized audio: peak \(String(format: "%.3f", peakFloat)) → \(String(format: "%.3f", targetPeak)) (gain: \(String(format: "%.1f", gain))x)")
            return normalizedURL
        }

        return wavURL
    }

    // MARK: - F6: Duration Check

    /// Returns the duration of a WAV file in seconds
    func wavDuration(at url: URL) -> Double {
        let fileSize = getFileSize(at: url)
        guard fileSize > 44 else { return 0 }
        // WAV: 16kHz, 16-bit, mono → 32000 bytes per second
        let audioBytes = Double(fileSize - 44)
        return audioBytes / (sampleRate * 2.0 * Double(channels))
    }

    /// Pads a WAV file with trailing silence so it meets the OpenAI API's 1-second minimum.
    /// Returns the original URL if already long enough.
    func padToMinimumDuration(wavURL: URL, minSeconds: Double = 1.0) -> URL {
        let duration = wavDuration(at: wavURL)
        guard duration < minSeconds else { return wavURL }

        guard let data = try? Data(contentsOf: wavURL) else { return wavURL }
        let headerSize = 44
        guard data.count > headerSize else { return wavURL }

        let sampleData = data.subdata(in: headerSize..<data.count)
        let existingSamples: [Int16] = sampleData.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: Int16.self)
            return Array(buffer)
        }

        let targetSampleCount = Int(minSeconds * sampleRate) * Int(channels)
        let paddingCount = targetSampleCount - existingSamples.count
        guard paddingCount > 0 else { return wavURL }

        let padded = existingSamples + [Int16](repeating: 0, count: paddingCount)

        let paddedURL = wavURL.deletingLastPathComponent()
            .appendingPathComponent("padded_\(wavURL.lastPathComponent)")

        if writeWAV(samples: padded, to: paddedURL) {
            try? FileManager.default.removeItem(at: wavURL)
            logToFile("[AudioRecorder] Padded audio: \(String(format: "%.2f", duration))s → \(String(format: "%.2f", minSeconds))s")
            return paddedURL
        }

        return wavURL
    }

    // MARK: - WAV Helpers

    private func rmsForRange(samples: [Int16], start: Int, end: Int) -> Float {
        var sum: Float = 0
        let count = end - start
        guard count > 0 else { return 0 }
        for i in start..<end {
            let s = Float(samples[i]) / Float(Int16.max)
            sum += s * s
        }
        return sqrt(sum / Float(count))
    }

    /// Writes Int16 samples as a 16kHz mono 16-bit WAV file
    private func writeWAV(samples: [Int16], to url: URL) -> Bool {
        let dataSize = samples.count * 2
        let fileSize = 44 + dataSize

        var header = Data(capacity: 44)
        // RIFF header
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Array($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        // fmt chunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM format
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // mono
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16000).littleEndian) { Array($0) }) // sample rate
        header.append(contentsOf: withUnsafeBytes(of: UInt32(32000).littleEndian) { Array($0) }) // byte rate
        header.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) }) // block align
        header.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // bits per sample
        // data chunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        var fileData = header
        samples.withUnsafeBufferPointer { buffer in
            fileData.append(UnsafeBufferPointer(start: UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UInt8.self), count: dataSize))
        }

        do {
            try fileData.write(to: url)
            return true
        } catch {
            logToFile("[AudioRecorder] Failed to write WAV: \(error.localizedDescription)")
            return false
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
