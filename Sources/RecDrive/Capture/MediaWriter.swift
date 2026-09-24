import Foundation
@preconcurrency import Dispatch
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
    private var latestPresentationTime: CMTime = .invalid
    private var isFinalizing = false
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
    
    private func beginFinalization() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isFinalizing && assetWriter?.status == .completed {
            return false
        }
        self.isFinalizing = true
        return true
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
            AVVideoAllowFrameReorderingKey: false
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
        self.latestPresentationTime = .invalid
        self.isFinalizing = false
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
        
        lock.lock()
        if isFinalizing {
            lock.unlock()
            return
        }
        lock.unlock()
        
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  let vInput = self.videoInput,
                  writer.status == .writing else { return }
            
            self.lock.lock()
            if self.isFinalizing {
                self.lock.unlock()
                return
            }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else {
                self.lock.unlock()
                return
            }
            
            if !self.isSessionStarted {
                writer.startSession(atSourceTime: pts)
                self.sessionStartTime = pts
                self.isSessionStarted = true
            }
            
            if pts > self.latestPresentationTime || !self.latestPresentationTime.isValid {
                self.latestPresentationTime = pts
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
        
        lock.lock()
        if isFinalizing {
            lock.unlock()
            return
        }
        lock.unlock()
        
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  let aInput = self.systemAudioInput,
                  writer.status == .writing else { return }
            
            self.lock.lock()
            if self.isFinalizing {
                self.lock.unlock()
                return
            }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else {
                self.lock.unlock()
                return
            }
            
            let started = self.isSessionStarted
            let startPts = self.sessionStartTime
            
            if started && pts >= startPts {
                if pts > self.latestPresentationTime || !self.latestPresentationTime.isValid {
                    self.latestPresentationTime = pts
                }
            }
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
        
        lock.lock()
        if isFinalizing {
            lock.unlock()
            return
        }
        lock.unlock()
        
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  let micInput = self.microphoneAudioInput,
                  writer.status == .writing else { return }
            
            self.lock.lock()
            if self.isFinalizing {
                self.lock.unlock()
                return
            }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else {
                self.lock.unlock()
                return
            }
            
            let started = self.isSessionStarted
            let startPts = self.sessionStartTime
            
            if started && pts >= startPts {
                if pts > self.latestPresentationTime || !self.latestPresentationTime.isValid {
                    self.latestPresentationTime = pts
                }
            }
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
        if !beginFinalization() {
            return outputURL
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()
            
            let safeResume: (Result<URL, Error>) -> Void = { result in
                resumeLock.lock()
                defer { resumeLock.unlock() }
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(with: result)
                }
            }
            
            // Timeout watchdog (15 seconds) to prevent infinite UI hangs
            let timeoutItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                print("[MediaWriter] finishWriting timeout (15s) reached! Cancelling writer.")
                self.assetWriter?.cancelWriting()
                safeResume(.failure(NSError(
                    domain: "RecDrive.MediaWriter",
                    code: -5,
                    userInfo: [NSLocalizedDescriptionKey: "Il salvataggio del video ha superato il tempo limite."]
                )))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15.0, execute: timeoutItem)
            
            writerQueue.async { [weak self] in
                guard let self = self, let writer = self.assetWriter else {
                    timeoutItem.cancel()
                    safeResume(.failure(NSError(domain: "RecDrive.MediaWriter", code: -3, userInfo: [NSLocalizedDescriptionKey: "Scrittura non attiva o già completata."])))
                    return
                }
                
                self.lock.lock()
                let started = self.isSessionStarted
                let startPts = self.sessionStartTime
                let endPts = self.latestPresentationTime
                self.lock.unlock()
                
                if writer.status == .writing {
                    // Explicitly end session at the maximum timestamp across all tracks
                    if started {
                        let finalEnd = (endPts.isValid && endPts >= startPts) ? endPts : CMClockGetTime(CMClockGetHostTimeClock())
                        writer.endSession(atSourceTime: finalEnd)
                    } else {
                        writer.startSession(atSourceTime: .zero)
                        writer.endSession(atSourceTime: .zero)
                    }
                    
                    self.videoInput?.markAsFinished()
                    self.systemAudioInput?.markAsFinished()
                    self.microphoneAudioInput?.markAsFinished()
                    
                    writer.finishWriting {
                        timeoutItem.cancel()
                        if writer.status == .completed {
                            safeResume(.success(self.outputURL))
                        } else if let error = writer.error {
                            print("[MediaWriter] finishWriting failed with error: \(error)")
                            safeResume(.failure(error))
                        } else {
                            safeResume(.success(self.outputURL))
                        }
                    }
                } else if writer.status == .completed {
                    timeoutItem.cancel()
                    safeResume(.success(self.outputURL))
                } else {
                    timeoutItem.cancel()
                    let error = writer.error ?? NSError(
                        domain: "RecDrive.MediaWriter",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Stato finale AVAssetWriter non valido: \(writer.status.rawValue)"]
                    )
                    print("[MediaWriter] finishWriting unexpected state: \(writer.status.rawValue), error: \(error)")
                    safeResume(.failure(error))
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
