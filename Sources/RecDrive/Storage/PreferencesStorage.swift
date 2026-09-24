import Foundation
import Combine

/// Manages application preferences persisted in UserDefaults.
public final class PreferencesStorage: ObservableObject {
    public static let shared = PreferencesStorage()
    
    private let defaults: UserDefaults
    
    private enum Keys {
        static let autoDeleteLocalFile = "com.recdrive.autoDeleteLocalFile"
        static let copyLinkToClipboard = "com.recdrive.copyLinkToClipboard"
        static let selectedDriveFolderId = "com.recdrive.selectedDriveFolderId"
        static let selectedDriveFolderName = "com.recdrive.selectedDriveFolderName"
        static let videoCodec = "com.recdrive.videoCodec"
        static let targetFrameRate = "com.recdrive.targetFrameRate"
        static let captureSystemAudio = "com.recdrive.captureSystemAudio"
        static let captureMicrophone = "com.recdrive.captureMicrophone"
        static let customClientId = "com.recdrive.customClientId"
        static let customClientSecret = "com.recdrive.customClientSecret"
        static let customRedirectUri = "com.recdrive.customRedirectUri"
    }
    
    @Published public var autoDeleteLocalFile: Bool {
        didSet { defaults.set(autoDeleteLocalFile, forKey: Keys.autoDeleteLocalFile) }
    }
    
    @Published public var copyLinkToClipboard: Bool {
        didSet { defaults.set(copyLinkToClipboard, forKey: Keys.copyLinkToClipboard) }
    }
    
    @Published public var selectedDriveFolderId: String? {
        didSet { defaults.set(selectedDriveFolderId, forKey: Keys.selectedDriveFolderId) }
    }
    
    @Published public var selectedDriveFolderName: String {
        didSet { defaults.set(selectedDriveFolderName, forKey: Keys.selectedDriveFolderName) }
    }
    
    @Published public var videoCodec: String {
        didSet { defaults.set(videoCodec, forKey: Keys.videoCodec) }
    }
    
    @Published public var targetFrameRate: Int {
        didSet { defaults.set(targetFrameRate, forKey: Keys.targetFrameRate) }
    }
    
    @Published public var captureSystemAudio: Bool {
        didSet { defaults.set(captureSystemAudio, forKey: Keys.captureSystemAudio) }
    }
    
    @Published public var captureMicrophone: Bool {
        didSet { defaults.set(captureMicrophone, forKey: Keys.captureMicrophone) }
    }
    
    @Published public var customClientId: String {
        didSet { defaults.set(customClientId, forKey: Keys.customClientId) }
    }
    
    @Published public var customClientSecret: String {
        didSet { defaults.set(customClientSecret, forKey: Keys.customClientSecret) }
    }
    
    @Published public var customRedirectUri: String {
        didSet { defaults.set(customRedirectUri, forKey: Keys.customRedirectUri) }
    }
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        self.autoDeleteLocalFile = defaults.bool(forKey: Keys.autoDeleteLocalFile)
        self.copyLinkToClipboard = defaults.object(forKey: Keys.copyLinkToClipboard) as? Bool ?? true
        self.selectedDriveFolderId = defaults.string(forKey: Keys.selectedDriveFolderId)
        self.selectedDriveFolderName = defaults.string(forKey: Keys.selectedDriveFolderName) ?? "Google Drive (Root)"
        self.videoCodec = defaults.string(forKey: Keys.videoCodec) ?? "hevc"
        self.targetFrameRate = defaults.object(forKey: Keys.targetFrameRate) as? Int ?? 60
        self.captureSystemAudio = defaults.object(forKey: Keys.captureSystemAudio) as? Bool ?? true
        self.captureMicrophone = defaults.bool(forKey: Keys.captureMicrophone)
        self.customClientId = defaults.string(forKey: Keys.customClientId) ?? ""
        self.customClientSecret = defaults.string(forKey: Keys.customClientSecret) ?? ""
        self.customRedirectUri = defaults.string(forKey: Keys.customRedirectUri) ?? ""
    }
    
    public func resetDefaults() {
        autoDeleteLocalFile = false
        copyLinkToClipboard = true
        selectedDriveFolderId = nil
        selectedDriveFolderName = "Google Drive (Root)"
        videoCodec = "hevc"
        targetFrameRate = 60
        captureSystemAudio = true
        captureMicrophone = false
        customClientId = ""
        customClientSecret = ""
        customRedirectUri = ""
    }
}
