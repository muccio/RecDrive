import Foundation
import SwiftUI
import ScreenCaptureKit
import AVFoundation

/// Central application state coordinator on the MainActor.
/// Connects capture pipeline, storage, OAuth authentication, and background Drive uploads.
@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    // Subsystem Singletons
    public let captureManager = ScreenCaptureManager.shared
    public let oauthManager = OAuthManager.shared
    public let driveService = DriveService.shared
    public let preferences = PreferencesStorage.shared
    public let storage = LocalStorageManager.shared
    
    // UI State
    @Published public var selectedTarget: CaptureTarget?
    @Published public var selectedTargetName: String = "Entire Screen"
    @Published public var isRecording: Bool = false
    @Published public var recordingDuration: TimeInterval = 0
    
    @Published public var isUploading: Bool = false
    @Published public var uploadProgressFraction: Double = 0.0
    @Published public var lastUploadedFileLink: String? = nil
    @Published public var statusMessage: String? = nil
    
    @Published public var hasScreenCapturePermission: Bool = true
    
    private var durationTimer: Timer?
    
    public init() {
        checkScreenCapturePermission()
    }
    
    // MARK: - Permissions
    
    public func checkScreenCapturePermission() {
        if #available(macOS 14.0, *) {
            // macOS 14+ ScreenCaptureKit preflight
            self.hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
        } else {
            // macOS 13 CGPreflight
            self.hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
        }
    }
    
    public func requestScreenCapturePermission() {
        CGRequestScreenCaptureAccess()
        checkScreenCapturePermission()
    }
    
    // MARK: - Start Recording
    
    public func startRecording() async {
        guard !isRecording else { return }
        
        // Refresh sources if no target selected
        if selectedTarget == nil {
            await captureManager.refreshShareableContent()
            if let firstDisplay = captureManager.availableDisplays.first {
                self.selectedTarget = .display(firstDisplay.scDisplay)
                self.selectedTargetName = firstDisplay.name
            }
        }
        
        guard let target = selectedTarget else {
            self.statusMessage = "Please select a display or window to record."
            return
        }
        
        let outputURL = storage.createRecordingURL(fileExtension: "mp4")
        let codec: AVVideoCodecType = (preferences.videoCodec == "h264") ? .h264 : .hevc
        
        do {
            try await captureManager.startCapture(
                target: target,
                outputURL: outputURL,
                fps: preferences.targetFrameRate,
                captureSystemAudio: preferences.captureSystemAudio,
                captureMicrophone: preferences.captureMicrophone,
                codec: codec
            )
            
            self.isRecording = true
            self.recordingDuration = 0
            self.statusMessage = "Recording started"
            
            StatusItemController.shared.updateState(.recording)
            
            // Local high-frequency UI timer for stopwatch display
            self.durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingDuration += 1.0
                }
            }
        } catch {
            self.statusMessage = "Failed to start capture: \(error.localizedDescription)"
            StatusItemController.shared.updateState(.idle)
        }
    }
    
    // MARK: - Stop Recording & Background Upload
    
    public func stopRecording() async {
        guard isRecording else { return }
        
        durationTimer?.invalidate()
        durationTimer = nil
        self.isRecording = false
        
        StatusItemController.shared.updateState(.stopping)
        
        do {
            let outputURL = try await captureManager.stopCapture()
            self.statusMessage = "Saved to \(outputURL.lastPathComponent)"
            
            // Check if user is signed in to Google Drive
            if oauthManager.isAuthenticated {
                await initiateBackgroundUpload(fileURL: outputURL)
            } else {
                StatusItemController.shared.updateState(.idle)
                self.statusMessage = "Recording saved locally. Sign in to Drive to enable auto-upload."
            }
        } catch {
            self.statusMessage = "Error stopping capture: \(error.localizedDescription)"
            StatusItemController.shared.updateState(.idle)
        }
    }
    
    // MARK: - Background Google Drive Upload
    
    private func initiateBackgroundUpload(fileURL: URL) async {
        self.isUploading = true
        self.uploadProgressFraction = 0.0
        StatusItemController.shared.updateState(.uploading(progress: 0.0))
        
        Task {
            do {
                let driveFile = try await DriveService.shared.uploadRecording(fileURL: fileURL) { progress in
                    Task { @MainActor in
                        self.uploadProgressFraction = progress.fractionCompleted
                        StatusItemController.shared.updateState(.uploading(progress: progress.fractionCompleted))
                    }
                }
                
                self.isUploading = false
                let link = driveFile.webViewLink ?? "https://drive.google.com/file/d/\(driveFile.id)/view"
                self.lastUploadedFileLink = link
                self.statusMessage = "✓ Uploaded to Google Drive!"
                StatusItemController.shared.updateState(.completed)
            } catch {
                self.isUploading = false
                self.statusMessage = "Upload error: \(error.localizedDescription)"
                StatusItemController.shared.updateState(.idle)
            }
        }
    }
}
