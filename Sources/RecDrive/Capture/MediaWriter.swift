import Foundation
@preconcurrency import Dispatch
import AVFoundation
import CoreMedia
import VideoToolbox

/// Non-blocking, hardware-accelerated media multiplexer using AVAssetWriter.
/// Directly encodes video frames from ScreenCaptureKit and audio tracks from system and microphone.
/// Supports both unified real-time audio mixing (combining system sound + voice into Track 1)
/// and multi-track audio recording for advanced post-production.
public final class MediaWriter: @unchecked Sendable {
    public let outputURL: URL
    private let videoWidth: Int
    private let videoHeight: Int
    private let fps: Int
    private let codec: AVVideoCodecType
    private let hasSystemAudio: Bool
    private let hasMicrophoneAudio: Bool
    private let microphoneSampleRate: Double
    private let microphoneChannels: Int
    private let mixAudioTracks: Bool
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    
    // Audio Inputs
    private var primaryAudioInput: AVAssetWriterInput?
    private var secondaryAudioInput: AVAssetWriterInput?
    private var audioMixer: RealTimeAudioMixer?
    
    private var isSessionStarted = false
    private var sessionStartTime: CMTime = .invalid
    private var latestPresentationTime: CMTime = .invalid
    private var isFinalizing = false
    private var hasAppendedVideo = false
    private var hasAppendedAudio = false
    
    // Strict monotonic timestamp trackers
    private var lastPrimaryAudioPTS: CMTime = .invalid
    private var lastSecondaryAudioPTS: CMTime = .invalid
    
    private let writerQueue = DispatchQueue(label: "com.recdrive.mediawriter", qos: .userInteractive)
    private let lock = NSLock()
    
    public init(
        outputURL: URL,
        videoWidth: Int,
        videoHeight: Int,
        fps: Int = 60,
        codec: AVVideoCodecType = .hevc,
        hasSystemAudio: Bool = true,
        hasMicrophoneAudio: Bool = false,
        microphoneSampleRate: Double = 48000.0,
        microphoneChannels: Int = 2,
        mixAudioTracks: Bool = true
    ) {
        self.outputURL = outputURL
        self.videoWidth = max(2, (videoWidth / 2) * 2)
        self.videoHeight = max(2, (videoHeight / 2) * 2)
        self.fps = max(15, fps)
        self.codec = codec
        self.hasSystemAudio = hasSystemAudio
        self.hasMicrophoneAudio = hasMicrophoneAudio
        self.microphoneSampleRate = microphoneSampleRate > 0 ? microphoneSampleRate : 48000.0
        self.microphoneChannels = min(max(microphoneChannels, 1), 2)
        self.mixAudioTracks = mixAudioTracks
    }
    
    private func beginFinalization() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isFinalizing {
            return false
        }
        self.isFinalizing = true
        return true
    }
    
    // MARK: - Setup and Start
    
    public func startWriting() throws {
        lock.lock()
        defer { lock.unlock() }
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = false
        writer.movieFragmentInterval = CMTime(seconds: 2.0, preferredTimescale: 600)
        
        // 1. Hardware Video Compression Settings
        let bitrate = calculateTargetBitrate(width: videoWidth, height: videoHeight)
        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps,
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
        
        // 2. Audio Configuration
        let isUnifiedMix = mixAudioTracks && hasSystemAudio && hasMicrophoneAudio
        
        if isUnifiedMix {
            // Unified Mixed Track (System Audio + Mic merged into Track 1)
            let masterAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: masterAudioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) {
                writer.add(aInput)
                self.primaryAudioInput = aInput
            }
            
            // Initialize RealTimeAudioMixer
            self.audioMixer = RealTimeAudioMixer { [weak self] mixedBuffer in
                self?.appendAudioSampleBufferInternal(mixedBuffer, isPrimary: true)
            }
        } else {
            // Standard or Separate Audio Tracks
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
                    self.primaryAudioInput = aInput
                }
            }
            
            if hasMicrophoneAudio {
                let micChannels = microphoneChannels
                let micAudioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: microphoneSampleRate,
                    AVNumberOfChannelsKey: micChannels,
                    AVEncoderBitRateKey: micChannels == 1 ? 96000 : 128000
                ]
                let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micAudioSettings)
                micInput.expectsMediaDataInRealTime = true
                if writer.canAdd(micInput) {
                    writer.add(micInput)
                    if self.primaryAudioInput == nil {
                        self.primaryAudioInput = micInput
                    } else {
                        self.secondaryAudioInput = micInput
                    }
                }
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
        
        if let mixer = audioMixer {
            mixer.appendSystemAudio(sampleBuffer)
            return
        }
        
        // Single track or unmixed separate tracks
        appendAudioSampleBufferInternal(sampleBuffer, isPrimary: true)
    }
    
    public func appendMicrophoneAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            return
        }
        
        if let mixer = audioMixer {
            mixer.appendMicrophoneAudio(sampleBuffer)
            return
        }
        
        // If system audio was present, mic goes to secondaryAudioInput. Otherwise it is primaryAudioInput.
        let isPrimary = (hasSystemAudio == false)
        appendAudioSampleBufferInternal(sampleBuffer, isPrimary: isPrimary)
    }
    
    private func appendAudioSampleBufferInternal(_ sampleBuffer: CMSampleBuffer, isPrimary: Bool) {
        lock.lock()
        if isFinalizing {
            lock.unlock()
            return
        }
        lock.unlock()
        
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  writer.status == .writing else { return }
            
            let targetInput = isPrimary ? self.primaryAudioInput : self.secondaryAudioInput
            guard let aInput = targetInput else { return }
            
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
            
            // Enforce strictly monotonic PTS to prevent AVAssetWriter fatal failures
            let lastPTS = isPrimary ? self.lastPrimaryAudioPTS : self.lastSecondaryAudioPTS
            let finalPTS: CMTime
            if lastPTS.isValid {
                let minPTS = lastPTS + CMTime(value: 1, timescale: 48000)
                finalPTS = (pts < minPTS) ? minPTS : pts
            } else {
                finalPTS = pts
            }
            
            if isPrimary {
                self.lastPrimaryAudioPTS = finalPTS
            } else {
                self.lastSecondaryAudioPTS = finalPTS
            }
            self.lock.unlock()
            
            guard started, finalPTS >= startPts else { return }
            
            // Adjust buffer PTS if needed
            let bufferToAppend: CMSampleBuffer
            if finalPTS == pts {
                bufferToAppend = sampleBuffer
            } else {
                var timing = CMSampleTimingInfo()
                let status = CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timing)
                if status == noErr {
                    timing.presentationTimeStamp = finalPTS
                } else {
                    timing = CMSampleTimingInfo(
                        duration: CMTime(value: 1, timescale: 48000),
                        presentationTimeStamp: finalPTS,
                        decodeTimeStamp: .invalid
                    )
                }
                var newBuffer: CMSampleBuffer?
                let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
                    allocator: kCFAllocatorDefault,
                    sampleBuffer: sampleBuffer,
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: &timing,
                    sampleBufferOut: &newBuffer
                )
                bufferToAppend = (copyStatus == noErr && newBuffer != nil) ? newBuffer! : sampleBuffer
            }
            
            if aInput.isReadyForMoreMediaData {
                let success = aInput.append(bufferToAppend)
                if success {
                    self.hasAppendedAudio = true
                } else {
                    print("[MediaWriter] appendAudioSampleBuffer failed. Status: \(writer.status.rawValue), error: \(String(describing: writer.error))")
                }
            }
        }
    }
    
    // MARK: - Finalize Writing
    
    public func finishWriting() async throws -> URL {
        if !beginFinalization() {
            return outputURL
        }
        
        // Flush any remaining samples in the audio mixer before closing
        audioMixer?.flush()
        
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
            
            let timeoutItem = DispatchWorkItem { [weak self] in
                print("[MediaWriter] finishWriting timeout (10s) reached! Resuming continuation and cancelling writer.")
                safeResume(.failure(NSError(
                    domain: "RecDrive.MediaWriter",
                    code: -5,
                    userInfo: [NSLocalizedDescriptionKey: "Il salvataggio del video ha superato il tempo limite."]
                )))
                DispatchQueue.global(qos: .utility).async {
                    self?.assetWriter?.cancelWriting()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10.0, execute: timeoutItem)
            
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
                    guard started && self.hasAppendedVideo else {
                        timeoutItem.cancel()
                        writer.cancelWriting()
                        safeResume(.failure(NSError(
                            domain: "RecDrive.MediaWriter",
                            code: -6,
                            userInfo: [NSLocalizedDescriptionKey: "Nessun fotogramma video ricevuto durante la registrazione."]
                        )))
                        return
                    }
                    
                    self.videoInput?.markAsFinished()
                    self.primaryAudioInput?.markAsFinished()
                    self.secondaryAudioInput?.markAsFinished()
                    
                    if endPts.isValid && endPts > startPts {
                        writer.endSession(atSourceTime: endPts)
                    }
                    
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
