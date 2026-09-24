import Foundation
import SwiftUI
import ScreenCaptureKit
import AVFoundation

/// Central application state coordinator on the MainActor.
/// Connects capture pipeline, storage, preferences, and UI state.
@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    // Subsystem Singletons
    public let captureManager = ScreenCaptureManager.shared
    public let preferences = PreferencesStorage.shared
    public let storage = LocalStorageManager.shared
    
    // UI State
    @Published public var selectedTarget: CaptureTarget?
    @Published public var selectedTargetName: String = "Schermo Intero"
    @Published public var lessonTitle: String = ""
    @Published public var isRecording: Bool = false
    @Published public var isFinishing: Bool = false
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var statusMessage: String? = nil
    @Published public var lastRecordedURL: URL? = nil
    @Published public var hasScreenCapturePermission: Bool = true
    
    private var durationTimer: Timer?
    
    public init() {
        self.lessonTitle = preferences.lastLessonTitle
        checkScreenCapturePermission()
    }
    
    // MARK: - Permissions
    
    public func checkScreenCapturePermission() {
        self.hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
    }
    
    public func requestScreenCapturePermission() {
        CGRequestScreenCaptureAccess()
        checkScreenCapturePermission()
    }
    
    public func openSystemSettingsScreenCapture() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func restartApp() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    // MARK: - Start Recording
    
    public func startRecording() async {
        guard !isRecording && !isFinishing else { return }
        
        checkScreenCapturePermission()
        guard hasScreenCapturePermission else {
            requestScreenCapturePermission()
            self.statusMessage = "Permesso registrazione schermo necessario."
            return
        }
        
        // Refresh sources if no target selected
        if selectedTarget == nil {
            await captureManager.refreshShareableContent()
            if let firstDisplay = captureManager.availableDisplays.first {
                self.selectedTarget = .display(firstDisplay.scDisplay)
                self.selectedTargetName = firstDisplay.name
            }
        }
        
        guard let target = selectedTarget else {
            self.statusMessage = "Seleziona uno schermo o una finestra da registrare."
            return
        }
        
        // Save current lesson title for convenience
        let trimmedTitle = lessonTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.lastLessonTitle = trimmedTitle
        
        let outputURL = storage.createRecordingURL(lessonTitle: trimmedTitle, fileExtension: "mp4")
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
            self.statusMessage = "Registrazione avviata..."
            self.lastRecordedURL = nil
            
            StatusItemController.shared.updateState(.recording)
            
            // High-frequency UI timer for stopwatch display
            self.durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingDuration += 1.0
                }
            }
        } catch {
            self.statusMessage = "Avvio registrazione fallito: \(error.localizedDescription)"
            StatusItemController.shared.updateState(.idle)
        }
    }
    
    // MARK: - Stop Recording
    
    public func stopRecording() async {
        guard isRecording && !isFinishing else { return }
        
        self.isFinishing = true
        durationTimer?.invalidate()
        durationTimer = nil
        
        StatusItemController.shared.updateState(.stopping)
        
        defer {
            self.isRecording = false
            self.isFinishing = false
        }
        
        do {
            let outputURL = try await captureManager.stopCapture()
            self.lastRecordedURL = outputURL
            let fileSize = storage.fileSize(at: outputURL)
            let formattedSize = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            self.statusMessage = "Salvato: \(outputURL.lastPathComponent) (\(formattedSize))"
            StatusItemController.shared.updateState(.completed)
        } catch {
            self.statusMessage = "Errore durante il salvataggio: \(error.localizedDescription)"
            StatusItemController.shared.updateState(.idle)
        }
    }
    
    // MARK: - File Actions
    
    public func openRecordingsFolder() {
        let dir = storage.recordingsDirectory
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }
    
    public func revealLastRecordingInFinder() {
        guard let url = lastRecordedURL ?? storage.listRecordings().first else {
            openRecordingsFolder()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    public func openLastRecordingFile() {
        guard let url = lastRecordedURL ?? storage.listRecordings().first else { return }
        NSWorkspace.shared.open(url)
    }
}
