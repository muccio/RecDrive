import Foundation
import ScreenCaptureKit
import CoreImage
import CoreMedia
import AVFoundation

/// Background screen capture streamer using ScreenCaptureKit.
/// Captures the active display at a downscaled resolution (max 1280px width) at 30 fps,
/// converts raw frames to compressed JPEG buffers via CIContext (quality 0.65),
/// and streams them to the connected iPad companion device.
@MainActor
public final class ScreenMirrorStreamer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public static let shared = ScreenMirrorStreamer()
    
    private var stream: SCStream?
    private var isStreaming = false
    private let streamQueue = DispatchQueue(label: "com.recdrive.mirror.stream", qos: .userInteractive)
    
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .priorityRequestLow: false
    ])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Streaming Lifecycle
    
    /// Starts the ScreenCaptureKit mirror stream for the active screen.
    public func startStreaming() {
        guard !isStreaming else { return }
        
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                
                // Select active target display from AppState or fallback to primary display
                let targetDisplay: SCDisplay
                if case .display(let selectedDisplay)? = AppState.shared.selectedTarget {
                    targetDisplay = selectedDisplay
                } else if let firstDisplay = content.displays.first {
                    targetDisplay = firstDisplay
                } else {
                    print("[ScreenMirrorStreamer] No displays found for mirroring")
                    return
                }
                
                let displayWidth = targetDisplay.width
                let displayHeight = targetDisplay.height
                
                // Scale width to max 1280px while strictly maintaining aspect ratio
                let targetWidth: Int = min(1280, displayWidth)
                let scale = Double(targetWidth) / Double(max(1, displayWidth))
                let targetHeight: Int = Int(Double(displayHeight) * scale)
                
                // Dimensions must be even integers for hardware pixel formats
                let finalWidth = max(2, (targetWidth / 2) * 2)
                let finalHeight = max(2, (targetHeight / 2) * 2)
                
                let filter = SCContentFilter(display: targetDisplay, excludingApplications: [], exceptingWindows: [])
                
                let config = SCStreamConfiguration()
                config.width = finalWidth
                config.height = finalHeight
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS target
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true
                config.scalesToFit = true
                
                let newStream = SCStream(filter: filter, configuration: config, delegate: self)
                try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: streamQueue)
                try await newStream.startCapture()
                
                self.stream = newStream
                self.isStreaming = true
                print("[ScreenMirrorStreamer] Mirroring active: \(finalWidth)x\(finalHeight) @ 30 FPS")
            } catch {
                print("[ScreenMirrorStreamer] Failed to start mirroring: \(error)")
                self.isStreaming = false
            }
        }
    }
    
    /// Stops the screen mirroring capture stream.
    public func stopStreaming() {
        guard isStreaming else { return }
        self.isStreaming = false
        
        if let activeStream = self.stream {
            self.stream = nil
            Task {
                do {
                    try await activeStream.stopCapture()
                    print("[ScreenMirrorStreamer] Mirroring stopped")
                } catch {
                    print("[ScreenMirrorStreamer] Error stopping stream: \(error)")
                }
            }
        }
    }
    
    // MARK: - SCStreamOutput
    
    nonisolated public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let jpegData = ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.65]
        ) else { return }
        
        iPadBridgeServer.shared.sendVideoFrame(jpegData)
    }
    
    // MARK: - SCStreamDelegate
    
    nonisolated public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenMirrorStreamer] Stream encountered error: \(error)")
        Task { @MainActor in
            self.isStreaming = false
            self.stream = nil
        }
    }
}
