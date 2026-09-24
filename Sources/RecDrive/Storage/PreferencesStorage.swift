import Foundation
import Combine

/// Manages application preferences persisted in UserDefaults.
public final class PreferencesStorage: ObservableObject {
    public static let shared = PreferencesStorage()
    
    private let defaults: UserDefaults
    
    private enum Keys {
        static let videoCodec = "com.recdrive.videoCodec"
        static let targetFrameRate = "com.recdrive.targetFrameRate"
        static let captureSystemAudio = "com.recdrive.captureSystemAudio"
        static let captureMicrophone = "com.recdrive.captureMicrophone"
        static let customRecordingsPath = "com.recdrive.customRecordingsPath"
        static let lastLessonTitle = "com.recdrive.lastLessonTitle"
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
    
    @Published public var customRecordingsPath: String {
        didSet { defaults.set(customRecordingsPath, forKey: Keys.customRecordingsPath) }
    }
    
    @Published public var lastLessonTitle: String {
        didSet { defaults.set(lastLessonTitle, forKey: Keys.lastLessonTitle) }
    }
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        self.videoCodec = defaults.string(forKey: Keys.videoCodec) ?? "hevc"
        self.targetFrameRate = defaults.object(forKey: Keys.targetFrameRate) as? Int ?? 60
        self.captureSystemAudio = defaults.object(forKey: Keys.captureSystemAudio) as? Bool ?? true
        self.captureMicrophone = defaults.bool(forKey: Keys.captureMicrophone)
        self.customRecordingsPath = defaults.string(forKey: Keys.customRecordingsPath) ?? ""
        self.lastLessonTitle = defaults.string(forKey: Keys.lastLessonTitle) ?? ""
    }
    
    public func resetDefaults() {
        videoCodec = "hevc"
        targetFrameRate = 60
        captureSystemAudio = true
        captureMicrophone = false
        customRecordingsPath = ""
        lastLessonTitle = ""
    }
}
