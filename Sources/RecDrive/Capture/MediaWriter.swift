import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox

/// Non-blocking, hardware-accelerated media multiplexer using AVAssetWriter.
/// Directly encodes video frames from ScreenCaptureKit and audio tracks from system and microphone.
public final class MediaWriter: @unchecked Sendable {
    public let outputURL: URL
    private let videoWidth: Int
    private let videoHeight: Int
    private let codec: AVVideoCodecType
    private let hasSystemAudio: Bool
    private let hasMicrophoneAudio: Bool
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneAudioInput: AVAssetWriterInput?
    
    private var isSessionStarted = false
    private var sessionStartTime: CMTime = .invalid
    private var hasAppendedVideo = false
    private var hasAppendedAudio = false
    private var hasAppendedMic = false
    
    private let writerQueue = DispatchQueue(label: "com.recdrive.mediawriter", qos: .userInteractive)
    private let lock = NSLock()
    
    public init(
        outputURL: URL,
        videoWidth: Int,
        videoHeight: Int,
        codec: AVVideoCodecType = .hevc,
        hasSystemAudio: Bool = true,
        hasMicrophoneAudio: Bool = false
    ) {
        self.outputURL = outputURL
        // Ensure even dimensions required by hardware encoders
        self.videoWidth = max(2, (videoWidth / 2) * 2)
        self.videoHeight = max(2, (videoHeight / 2) * 2)
        self.codec = codec
        self.hasSystemAudio = hasSystemAudio
        self.hasMicrophoneAudio = hasMicrophoneAudio
    }
    
    // MARK: - Setup and Start
    
    public func startWriting() throws {
        lock.lock()
        defer { lock.unlock() }
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        // Set shouldOptimizeForNetworkUse to false so writes go directly to output file
        // preventing empty 0kb files and sidecar leftovers.
        writer.shouldOptimizeForNetworkUse = false
        
        // 1. Hardware Video Compression Settings
        let bitrate = calculateTargetBitrate(width: videoWidth, height: videoHeight)
        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: 60,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoAllowFrameReorderingKey: true
        ]
        
        if codec == .hevc {
            compressionProps[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: compressionProps
        ]
        
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(vInput) else {
            throw NSError(domain: "RecDrive.MediaWriter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Impossibile aggiungere video input ad AVAssetWriter."])
        }
        writer.add(vInput)
        self.videoInput = vInput
        
        // 2. System Audio Settings (AAC 48kHz Stereo)
        if hasSystemAudio {
            let systemAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: systemAudioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) {
                writer.add(aInput)
                self.systemAudioInput = aInput
            }
        }
        
        // 3. Microphone Audio Settings (AAC 48kHz Stereo)
        if hasMicrophoneAudio {
            let micAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micAudioSettings)
            micInput.expectsMediaDataInRealTime = true
            if writer.canAdd(micInput) {
                writer.add(micInput)
                self.microphoneAudioInput = micInput
            }
        }
        
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "RecDrive.MediaWriter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Errore durante l'avvio di AVAssetWriter."])
        }
        
        self.assetWriter = writer
        self.isSessionStarted = false
        self.sessionStartTime = .invalid
        self.hasAppendedVideo = false
        self.hasAppendedAudio = false
        self.hasAppendedMic = false
    }
    
    // MARK: - Append Video Sample Buffer
    
    public func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid,
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
            return
        }
        
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  let vInput = self.videoInput,
                  writer.status == .writing else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else { return }
            
            self.lock.lock()
            if !self.isSessionStarted {
                writer.startSession(atSourceTime: pts)
                self.sessionStartTime = pts
                self.isSessionStarted = true
            }
            self.lock.unlock()
            
            if vInput.isReadyForMoreMediaData {
                let success = vInput.append(sampleBuffer)
                if success {
                    self.hasAppendedVideo = true
                } else {
                    print("[MediaWriter] appendVideoSampleBuffer failed. Status: \(writer.status.rawValue), error: \(String(describing: writer.error))")
                }
            }
        }
    }
    
    // MARK: - Append Audio Sample Buffers
    
    public func appendSystemAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            return
        }
        
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  let aInput = self.systemAudioInput,
                  writer.status == .writing else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else { return }
            
            self.lock.lock()
            let started = self.isSessionStarted
            let startPts = self.sessionStartTime
            self.lock.unlock()
            
            guard started, pts >= startPts else { return }
            
            if aInput.isReadyForMoreMediaData {
                let success = aInput.append(sampleBuffer)
                if success {
                    self.hasAppendedAudio = true
                }
            }
        }
    }
    
    public func appendMicrophoneAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            return
        }
        
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  let micInput = self.microphoneAudioInput,
                  writer.status == .writing else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else { return }
            
            self.lock.lock()
            let started = self.isSessionStarted
            let startPts = self.sessionStartTime
            self.lock.unlock()
            
            guard started, pts >= startPts else { return }
            
            if micInput.isReadyForMoreMediaData {
                let success = micInput.append(sampleBuffer)
                if success {
                    self.hasAppendedMic = true
                }
            }
        }
    }
    
    // MARK: - Finalize Writing
    
    public func finishWriting() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            writerQueue.async { [weak self] in
                guard let self = self, let writer = self.assetWriter else {
                    continuation.resume(throwing: NSError(domain: "RecDrive.MediaWriter", code: -3, userInfo: [NSLocalizedDescriptionKey: "Scrittura non attiva o già completata."]))
                    return
                }
                
                self.lock.lock()
                let started = self.isSessionStarted
                self.lock.unlock()
                
                // If session never started, start at .zero to allow clean finalization
                if !started && writer.status == .writing {
                    writer.startSession(atSourceTime: .zero)
                }
                
                if writer.status == .writing {
                    self.videoInput?.markAsFinished()
                    self.systemAudioInput?.markAsFinished()
                    self.microphoneAudioInput?.markAsFinished()
                    
                    writer.finishWriting {
                        if writer.status == .completed {
                            continuation.resume(returning: self.outputURL)
                        } else if let error = writer.error {
                            print("[MediaWriter] finishWriting failed with error: \(error)")
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: self.outputURL)
                        }
                    }
                } else if writer.status == .completed {
                    continuation.resume(returning: self.outputURL)
                } else {
                    let error = writer.error ?? NSError(
                        domain: "RecDrive.MediaWriter",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Stato finale AVAssetWriter non valido: \(writer.status.rawValue)"]
                    )
                    print("[MediaWriter] finishWriting unexpected state: \(writer.status.rawValue), error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func calculateTargetBitrate(width: Int, height: Int) -> Int {
        let pixels = width * height
        if pixels >= 3840 * 2160 {
            return 25_000_000 // 25 Mbps for 4K
        } else if pixels >= 2560 * 1440 {
            return 16_000_000 // 16 Mbps for 1440p
        } else if pixels >= 1920 * 1080 {
            return 10_000_000 // 10 Mbps for 1080p
        } else {
            return 6_000_000  // 6 Mbps for standard window
        }
    }
}
