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
        guard case .idle = recordingState else { return }
        self.recordingState = .preparing
        
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
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // NV12
        config.showsCursor = true
        config.capturesAudio = captureSystemAudio
        if captureSystemAudio {
            config.sampleRate = 48000
            config.channelCount = 2
        }
        
        // 3. Initialize Hardware-Accelerated MediaWriter
        let writer = MediaWriter(
            outputURL: outputURL,
            videoWidth: width,
            videoHeight: height,
            codec: codec,
            hasSystemAudio: captureSystemAudio,
            hasMicrophoneAudio: captureMicrophone
        )
        try writer.startWriting()
        self.mediaWriter = writer
        
        // 4. Start Microphone Capture if requested
        if captureMicrophone {
            try? micEngine.startCapture { [weak writer] micSampleBuffer in
                writer?.appendMicrophoneAudioSampleBuffer(micSampleBuffer)
            }
        }
        
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
                self.recordingState = .recording(elapsed: elapsed)
            }
        }
    }
    
    // MARK: - Stop Capture
    
    @MainActor
    public func stopCapture() async throws -> URL {
        guard case .recording = recordingState else {
            throw NSError(domain: "RecDrive.Capture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nessuna registrazione attiva da fermare."])
        }
        self.recordingState = .finishing
        
        timer?.invalidate()
        timer = nil
        
        // Stop ScreenCaptureKit stream first
        if let scStream = stream {
            try? await scStream.stopCapture()
            self.stream = nil
        }
        
        // Stop Microphone Engine
        micEngine.stopCapture()
        
        // Finalize MediaWriter
        guard let writer = mediaWriter else {
            self.recordingState = .idle
            throw NSError(domain: "RecDrive.Capture", code: -2, userInfo: [NSLocalizedDescriptionKey: "Scrittura file non disponibile."])
        }
        
        do {
            let outputURL = try await writer.finishWriting()
            self.mediaWriter = nil
            self.recordingState = .idle
            self.recordingStartTime = nil
            return outputURL
        } catch {
            self.mediaWriter = nil
            self.recordingState = .failed(error.localizedDescription)
            self.recordingStartTime = nil
            throw error
        }
    }
}

// MARK: - SCStreamOutput & SCStreamDelegate Callbacks

extension ScreenCaptureManager: SCStreamOutput, SCStreamDelegate {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let writer = mediaWriter, sampleBuffer.isValid else { return }
        
        switch type {
        case .screen:
            // Check frame status: drop frames that are not complete (e.g. idle, blank, suspended)
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first,
                  let statusRaw = attachments[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw),
                  status == .complete,
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
            self.recordingState = .failed(error.localizedDescription)
        }
    }
}
