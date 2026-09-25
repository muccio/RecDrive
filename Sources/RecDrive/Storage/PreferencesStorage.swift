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
        static let annotationHotKeyEnabled = "com.recdrive.annotationHotKeyEnabled"
        static let annotationHotKeyKeyCode = "com.recdrive.annotationHotKeyKeyCode"
        static let annotationHotKeyModifiers = "com.recdrive.annotationHotKeyModifiers"
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
    
    @Published public var annotationHotKeyEnabled: Bool {
        didSet { defaults.set(annotationHotKeyEnabled, forKey: Keys.annotationHotKeyEnabled) }
    }
    
    @Published public var annotationHotKeyKeyCode: Int {
        didSet { defaults.set(annotationHotKeyKeyCode, forKey: Keys.annotationHotKeyKeyCode) }
    }
    
    @Published public var annotationHotKeyModifiers: UInt32 {
        didSet { defaults.set(Int(annotationHotKeyModifiers), forKey: Keys.annotationHotKeyModifiers) }
    }
    
    @MainActor
    public var annotationHotKeyDisplayString: String {
        guard annotationHotKeyEnabled else { return "Disabilitata" }
        return HotKeyManager.displayString(keyCode: annotationHotKeyKeyCode, modifiers: annotationHotKeyModifiers)
    }
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        self.videoCodec = defaults.string(forKey: Keys.videoCodec) ?? "hevc"
        self.targetFrameRate = defaults.object(forKey: Keys.targetFrameRate) as? Int ?? 60
        self.captureSystemAudio = defaults.object(forKey: Keys.captureSystemAudio) as? Bool ?? true
        self.captureMicrophone = defaults.bool(forKey: Keys.captureMicrophone)
        self.customRecordingsPath = defaults.string(forKey: Keys.customRecordingsPath) ?? ""
        self.lastLessonTitle = defaults.string(forKey: Keys.lastLessonTitle) ?? ""
        
        self.annotationHotKeyEnabled = defaults.object(forKey: Keys.annotationHotKeyEnabled) as? Bool ?? true
        self.annotationHotKeyKeyCode = defaults.object(forKey: Keys.annotationHotKeyKeyCode) as? Int ?? 2 // kVK_ANSI_D
        self.annotationHotKeyModifiers = UInt32(defaults.object(forKey: Keys.annotationHotKeyModifiers) as? Int ?? 768) // cmdKey | shiftKey
    }
    
    public func resetDefaults() {
        videoCodec = "hevc"
        targetFrameRate = 60
        captureSystemAudio = true
        captureMicrophone = false
        customRecordingsPath = ""
        lastLessonTitle = ""
        annotationHotKeyEnabled = true
        annotationHotKeyKeyCode = 2
        annotationHotKeyModifiers = 768
    }
}
