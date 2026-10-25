import Foundation
import ScreenCaptureKit
import AVFoundation
import AppKit

/// Core controller orchestrating ScreenCaptureKit screen/window capture,
/// system audio interception, and external microphone synchronization.
public final class ScreenCaptureManager: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = ScreenCaptureManager()
    
    @Published public private(set) var recordingState: RecordingState = .idle
    @Published public private(set) var availableDisplays: [DisplayItem] = []
    @Published public private(set) var availableWindows: [WindowItem] = []
    
    private var stream: SCStream?
    private var mediaWriter: MediaWriter?
    private let micEngine = MicrophoneEngine()
    
    private var timer: Timer?
    private var recordingStartTime: Date?
    private let captureQueue = DispatchQueue(label: "com.recdrive.captureQueue", qos: .userInteractive)
    
    public override init() {
        super.init()
    }
    
    // MARK: - Query Shareable Content
    
    @MainActor
    public func refreshShareableContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            AppState.shared.hasScreenCapturePermission = true
            
            self.availableDisplays = content.displays.enumerated().map { index, display in
                DisplayItem(display: display, index: index)
            }
            
            // Filter out system UI elements, dock, menu bar windows and zero-sized windows
            self.availableWindows = content.windows
                .filter { window in
                    guard let app = window.owningApplication else { return false }
                    let bundleId = app.bundleIdentifier.lowercased()
                    let isSystemUI = bundleId.contains("dock") || bundleId.contains("systemuiserver") || bundleId.contains("controlcenter")
                    return !isSystemUI && window.frame.width > 50 && window.frame.height > 50
                }
                .map { WindowItem(window: $0) }
        } catch {
            print("[ScreenCaptureManager] Failed to fetch shareable content: \(error)")
            AppState.shared.hasScreenCapturePermission = false
        }
    }
    
    // MARK: - Start Capture
    
    @MainActor
    public func startCapture(
        target: CaptureTarget,
        outputURL: URL,
        fps: Int = 60,
        captureSystemAudio: Bool = true,
        captureMicrophone: Bool = false,
        codec: AVVideoCodecType = .hevc
    ) async throws {
        switch recordingState {
        case .idle, .failed:
            break
        case .preparing, .recording, .finishing:
            throw NSError(
                domain: "RecDrive.Capture",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Una registrazione è già in corso o in fase di chiusura."]
            )
        }
        
        self.recordingState = .preparing
        
        // Clean up any lingering previous session state
        timer?.invalidate()
        timer = nil
        micEngine.stopCapture()
        if let oldStream = self.stream {
            self.stream = nil
            Task.detached {
                try? await oldStream.stopCapture()
            }
        }
        self.mediaWriter = nil
        
        do {
            // 1. Determine filter and dimensions
            let filter: SCContentFilter
            var width: Int
            var height: Int
            
            switch target {
            case .display(let display):
                filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                width = display.width
                height = display.height
            case .window(let window):
                filter = SCContentFilter(desktopIndependentWindow: window)
                width = Int(window.frame.width)
                height = Int(window.frame.height)
            }
            
            // Ensure even dimensions required by hardware encoders
            width = max(2, (width / 2) * 2)
            height = max(2, (height / 2) * 2)
            
            // 2. Configure Stream Properties
            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(15, fps)))
            config.queueDepth = 6
            config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // NV12
            config.showsCursor = true
            config.capturesAudio = captureSystemAudio
            if captureSystemAudio {
                config.sampleRate = 48000
                config.channelCount = 2
            }
            
            // 3. Start Microphone Capture first (if requested) so we know its exact channel count & status
            var micActive = false
            if captureMicrophone {
                do {
                    try micEngine.startCapture { [weak self] micSampleBuffer in
                        self?.mediaWriter?.appendMicrophoneAudioSampleBuffer(micSampleBuffer)
                    }
                    micActive = true
                } catch {
                    print("[ScreenCaptureManager] Microphone start failed, continuing without mic track: \(error)")
                    micActive = false
                }
            }
            
            // 4. Initialize Hardware-Accelerated MediaWriter
            let writer = MediaWriter(
                outputURL: outputURL,
                videoWidth: width,
                videoHeight: height,
                fps: fps,
                codec: codec,
                hasSystemAudio: captureSystemAudio,
                hasMicrophoneAudio: micActive,
                microphoneSampleRate: micEngine.sampleRate,
                microphoneChannels: micEngine.channelCount
            )
            try writer.startWriting()
            self.mediaWriter = writer
            
            // 5. Initialize and Start SCStream
            let scStream = SCStream(filter: filter, configuration: config, delegate: self)
            try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            if captureSystemAudio {
                try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
            }
            
            try await scStream.startCapture()
            self.stream = scStream
            
            // 6. Start Timer for UI state
            self.recordingStartTime = Date()
            self.recordingState = .recording(elapsed: 0)
            
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self, let start = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(start)
                Task { @MainActor in
                    guard case .recording = self.recordingState else { return }
                    self.recordingState = .recording(elapsed: elapsed)
                }
            }
        } catch {
            micEngine.stopCapture()
            self.mediaWriter = nil
            self.stream = nil
            self.recordingState = .idle
            throw error
        }
    }
    
    // MARK: - Stop Capture
    
    @MainActor
    public func stopCapture() async throws -> URL {
        guard case .recording = recordingState else {
            self.recordingState = .idle
            throw NSError(domain: "RecDrive.Capture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nessuna registrazione attiva da fermare."])
        }
        self.recordingState = .finishing
        
        timer?.invalidate()
        timer = nil
        
        // 1. Instantly stop microphone ingress
        micEngine.stopCapture()
        
        // 2. Detach and stop ScreenCaptureKit stream with a non-blocking 2-second timeout
        if let scStream = self.stream {
            self.stream = nil
            await stopSCStreamWithTimeout(scStream, timeoutSeconds: 2.0)
        }
        
        let writer = self.mediaWriter
        self.mediaWriter = nil
        self.recordingStartTime = nil
        
        // 3. Finalize MediaWriter
        guard let activeWriter = writer else {
            self.recordingState = .idle
            throw NSError(domain: "RecDrive.Capture", code: -2, userInfo: [NSLocalizedDescriptionKey: "Scrittura file non disponibile."])
        }
        
        do {
            let outputURL = try await activeWriter.finishWriting()
            self.recordingState = .idle
            return outputURL
        } catch {
            self.recordingState = .idle
            throw error
        }
    }
    
    private func stopSCStreamWithTimeout(_ scStream: SCStream, timeoutSeconds: Double) async {
        final class ContinuationGate: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<Void, Never>?
            init(_ continuation: CheckedContinuation<Void, Never>) {
                self.continuation = continuation
            }
            func resumeOnce() {
                lock.lock()
                let cont = continuation
                continuation = nil
                lock.unlock()
                cont?.resume()
            }
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = ContinuationGate(continuation)
            
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeoutSeconds) {
                gate.resumeOnce()
            }
            
            Task.detached(priority: .userInitiated) { [weak self] in
                try? await scStream.stopCapture()
                if let self = self {
                    try? scStream.removeStreamOutput(self, type: .screen)
                    try? scStream.removeStreamOutput(self, type: .audio)
                }
                gate.resumeOnce()
            }
        }
    }
}

// MARK: - SCStreamOutput & SCStreamDelegate Callbacks

extension ScreenCaptureManager: SCStreamOutput, SCStreamDelegate {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard stream === self.stream, let writer = mediaWriter, sampleBuffer.isValid else { return }
        
        switch type {
        case .screen:
            // Check frame status: accept both complete and idle frames (which keep video timebase aligned with audio during static screen)
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first,
                  let statusRaw = attachments[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw),
                  (status == .complete || status == .idle),
                  CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
                return
            }
            writer.appendVideoSampleBuffer(sampleBuffer)
            
        case .audio:
            guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
            writer.appendSystemAudioSampleBuffer(sampleBuffer)
            
        case .microphone:
            guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
            writer.appendMicrophoneAudioSampleBuffer(sampleBuffer)
            
        @unknown default:
            break
        }
    }
    
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCaptureManager] Stream stopped with error: \(error)")
        Task { @MainActor in
            guard stream === self.stream, case .recording = self.recordingState else { return }
            self.recordingState = .failed(error.localizedDescription)
        }
    }
}
