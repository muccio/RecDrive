import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox

/// Non-blocking, hardware-accelerated media multiplexer using AVAssetWriter.
/// Directly encodes NV12 frames from ScreenCaptureKit via Apple Silicon VideoToolbox
/// and compresses system and microphone audio into AAC tracks.
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
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
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
        writer.shouldOptimizeForNetworkUse = true
        
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
            throw NSError(domain: "RecDrive.MediaWriter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input to AVAssetWriter."])
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
            throw writer.error ?? NSError(domain: "RecDrive.MediaWriter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to start AVAssetWriter."])
        }
        
        self.assetWriter = writer
        self.isSessionStarted = false
        self.sessionStartTime = .invalid
    }
    
    // MARK: - Append Video Sample Buffer
    
    public func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
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
                vInput.append(sampleBuffer)
            }
        }
    }
    
    // MARK: - Append Audio Sample Buffers
    
    public func appendSystemAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  let aInput = self.systemAudioInput,
                  writer.status == .writing else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else { return }
            
            // Drop audio packets before video session has initialized
            self.lock.lock()
            let started = self.isSessionStarted
            let startPts = self.sessionStartTime
            self.lock.unlock()
            
            guard started, pts >= startPts else { return }
            
            if aInput.isReadyForMoreMediaData {
                aInput.append(sampleBuffer)
            }
        }
    }
    
    public func appendMicrophoneAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
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
                micInput.append(sampleBuffer)
            }
        }
    }
    
    // MARK: - Finalize Writing
    
    public func finishWriting() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            writerQueue.async { [weak self] in
                guard let self = self, let writer = self.assetWriter else {
                    continuation.resume(throwing: NSError(domain: "RecDrive.MediaWriter", code: -3, userInfo: [NSLocalizedDescriptionKey: "No active writer found."]))
                    return
                }
                
                self.videoInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.microphoneAudioInput?.markAsFinished()
                
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: self.outputURL)
                    } else if let error = writer.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: self.outputURL)
                    }
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
