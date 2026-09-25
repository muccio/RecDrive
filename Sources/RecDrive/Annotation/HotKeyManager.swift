import Foundation
import AppKit
import Carbon

/// Manages global system-wide keyboard shortcuts using macOS Carbon EventHotKey API.
/// Does not require Accessibility permissions and functions across all active applications.
@MainActor
public final class HotKeyManager: @unchecked Sendable {
    public static let shared = HotKeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x52445256), id: 1) // 'RDRV', 1
    
    public init() {
        installCarbonHandler()
    }
    
    private func installCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (callRef, eventRef, userData) -> OSStatus in
                guard let eventRef = eventRef else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr && hotKeyID.id == 1 {
                    DispatchQueue.main.async {
                        AnnotationManager.shared.toggleAnnotation()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        if status != noErr {
            print("[HotKeyManager] Failed to install Carbon event handler, status: \(status)")
        }
    }
    
    public func registerFromPreferences() {
        let prefs = PreferencesStorage.shared
        guard prefs.annotationHotKeyEnabled else {
            unregisterAnnotationHotKey()
            return
        }
        registerAnnotationHotKey(keyCode: prefs.annotationHotKeyKeyCode, modifiers: prefs.annotationHotKeyModifiers)
    }
    
    public func registerAnnotationHotKey(keyCode: Int, modifiers: UInt32) {
        unregisterAnnotationHotKey()
        
        guard PreferencesStorage.shared.annotationHotKeyEnabled else { return }
        
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            self.hotKeyRef = ref
            print("[HotKeyManager] Registered global hotkey: keyCode \(keyCode), modifiers \(modifiers)")
        } else {
            print("[HotKeyManager] Failed to register global hotkey, status: \(status)")
        }
    }
    
    public func unregisterAnnotationHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
    
    // MARK: - Helper Formatting & Conversions
    
    public static func displayString(keyCode: Int, modifiers: UInt32) -> String {
        let modStr = stringForModifiers(modifiers)
        let keyStr = stringForKeyCode(keyCode)
        if modStr.isEmpty {
            return keyStr
        }
        return "\(modStr) \(keyStr)"
    }
    
    public static func stringForModifiers(_ modifiers: UInt32) -> String {
        var parts: [String] = []
        if (modifiers & UInt32(controlKey)) != 0 { parts.append("⌃") }
        if (modifiers & UInt32(optionKey)) != 0 { parts.append("⌥") }
        if (modifiers & UInt32(shiftKey)) != 0 { parts.append("⇧") }
        if (modifiers & UInt32(cmdKey)) != 0 { parts.append("⌘") }
        return parts.joined(separator: " ")
    }
    
    public static func carbonModifiers(from cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoaFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if cocoaFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if cocoaFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if cocoaFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }
    
    public static func stringForKeyCode(_ keyCode: Int) -> String {
        switch keyCode {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Space: return "Spazio"
        case kVK_Return: return "Invio"
        case kVK_Tab: return "Tab"
        default: return "Tasto \(keyCode)"
        }
    }
}
