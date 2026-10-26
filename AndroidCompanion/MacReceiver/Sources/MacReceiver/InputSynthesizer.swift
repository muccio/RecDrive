import Foundation
import CoreGraphics
import AppKit

/// Synthesizes native macOS keyboard and mouse events using Quartz Event Services (CGEvent).
public final class InputSynthesizer: @unchecked Sendable {
    public static let shared = InputSynthesizer()
    
    private init() {}
    
    // MARK: - Accessibility Permissions
    
    /// Checks if this process has accessibility permissions required to synthesize system events.
    public func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Prompts the user to grant accessibility permissions in System Settings -> Privacy & Security.
    public func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Command Execution
    
    public func execute(_ command: IncomingCommand) {
        switch command.type {
        case "presentation":
            if let action = command.action {
                handlePresentationAction(action)
            }
            
        case "key":
            if let code = command.code {
                let flags = parseModifiers(command.modifiers)
                sendKeyPress(keyCode: CGKeyCode(code), flags: flags)
            }
            
        case "shortcut":
            if let name = command.name {
                handleShortcut(name)
            }
            
        case "mouse_move":
            let dx = CGFloat(command.dx ?? 0.0)
            let dy = CGFloat(command.dy ?? 0.0)
            moveMouse(dx: dx, dy: dy)
            
        case "mouse_click":
            let button = command.button?.lowercased() ?? "left"
            clickMouse(buttonName: button)
            
        case "mouse_scroll":
            let dx = CGFloat(command.dx ?? 0.0)
            let dy = CGFloat(command.dy ?? 0.0)
            scrollMouse(dx: dx, dy: dy)
            
        case "text":
            if let text = command.text {
                sendUnicodeText(text)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Presentation Actions
    
    private func handlePresentationAction(_ action: String) {
        switch action.lowercased() {
        case "next":
            // Right Arrow advances slides/animations in Keynote, PowerPoint, Google Slides, Preview
            sendKeyPress(keyCode: 124) // Right Arrow
            
        case "prev", "previous":
            // Left Arrow goes back in slides/animations
            sendKeyPress(keyCode: 123) // Left Arrow
            
        case "play", "start":
            // Option + Command + P plays slideshow from beginning in Keynote
            sendKeyPress(keyCode: 35, flags: [.maskAlternate, .maskCommand]) // 'p' with ⌥⌘
            // Also send F5 as fallback for PowerPoint / Google Slides
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                self.sendKeyPress(keyCode: 96) // F5
            }
            
        case "escape", "stop", "exit":
            // Escape exits presentation
            sendKeyPress(keyCode: 53) // Escape
            
        case "black_screen", "black":
            // 'B' toggles black screen in Keynote & PowerPoint
            sendKeyPress(keyCode: 11) // 'b'
            
        case "white_screen", "white":
            // 'W' toggles white screen in Keynote & PowerPoint
            sendKeyPress(keyCode: 13) // 'w'
            
        default:
            break
        }
    }
    
    // MARK: - Shortcuts
    
    private func handleShortcut(_ name: String) {
        switch name.lowercased() {
        case "space":
            sendKeyPress(keyCode: 49)
        case "enter", "return":
            sendKeyPress(keyCode: 36)
        case "escape", "esc":
            sendKeyPress(keyCode: 53)
        case "tab":
            sendKeyPress(keyCode: 48)
        case "backspace", "delete":
            sendKeyPress(keyCode: 51)
        case "up":
            sendKeyPress(keyCode: 126)
        case "down":
            sendKeyPress(keyCode: 125)
        case "left":
            sendKeyPress(keyCode: 123)
        case "right":
            sendKeyPress(keyCode: 124)
            
        case "app_switch":
            // Command + Tab
            sendKeyPress(keyCode: 48, flags: [.maskCommand])
            
        case "mission_control":
            // Control + Up Arrow
            sendKeyPress(keyCode: 126, flags: [.maskControl])
            
        case "spotlight":
            // Command + Space
            sendKeyPress(keyCode: 49, flags: [.maskCommand])
            
        case "volume_up":
            adjustSystemVolume(delta: 6)
            
        case "volume_down":
            adjustSystemVolume(delta: -6)
            
        case "mute":
            toggleSystemMute()
            
        case "play_pause":
            // Space or media play
            sendKeyPress(keyCode: 49)
            
        default:
            break
        }
    }
    
    // MARK: - Low-level CGEvent Dispatch
    
    public func sendKeyPress(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        if !flags.isEmpty {
            keyDown.flags = flags
            keyUp.flags = flags
        }
        
        keyDown.post(tap: .cghidEventTap)
        usleep(15_000) // 15ms hold duration
        keyUp.post(tap: .cghidEventTap)
    }
    
    public func moveMouse(dx: CGFloat, dy: CGFloat) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let newX = max(0, currentPos.x + dx)
        let newY = max(0, currentPos.y + dy)
        let newPos = CGPoint(x: newX, y: newY)
        
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newPos, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)
    }
    
    public func clickMouse(buttonName: String) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        
        switch buttonName {
        case "right":
            let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: currentPos, mouseButton: .right)
            let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: currentPos, mouseButton: .right)
            down?.post(tap: .cghidEventTap)
            usleep(10_000)
            up?.post(tap: .cghidEventTap)
            
        case "double":
            let down1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: currentPos, mouseButton: .left)
            let up1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: currentPos, mouseButton: .left)
            down1?.setIntegerValueField(.mouseEventClickState, value: 1)
            up1?.setIntegerValueField(.mouseEventClickState, value: 1)
            down1?.post(tap: .cghidEventTap)
            up1?.post(tap: .cghidEventTap)
            
            usleep(25_000)
            
            let down2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: currentPos, mouseButton: .left)
            let up2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: currentPos, mouseButton: .left)
            down2?.setIntegerValueField(.mouseEventClickState, value: 2)
            up2?.setIntegerValueField(.mouseEventClickState, value: 2)
            down2?.post(tap: .cghidEventTap)
            up2?.post(tap: .cghidEventTap)
            
        default: // left
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: currentPos, mouseButton: .left)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: currentPos, mouseButton: .left)
            down?.setIntegerValueField(.mouseEventClickState, value: 1)
            up?.setIntegerValueField(.mouseEventClickState, value: 1)
            down?.post(tap: .cghidEventTap)
            usleep(10_000)
            up?.post(tap: .cghidEventTap)
        }
    }
    
    public func scrollMouse(dx: CGFloat, dy: CGFloat) {
        let scroll = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(dy),
            wheel2: Int32(dx),
            wheel3: 0
        )
        scroll?.post(tap: .cghidEventTap)
    }
    
    public func sendUnicodeText(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for char in text.utf16 {
            var unichar = char
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            keyDown?.post(tap: .cghidEventTap)
            usleep(5_000)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Audio Utilities via AppleScript
    
    private func adjustSystemVolume(delta: Int) {
        let scriptText: String
        if delta > 0 {
            scriptText = "set volume output volume (min(100, (output volume of (get volume settings)) + \(delta)))"
        } else {
            scriptText = "set volume output volume (max(0, (output volume of (get volume settings)) \(delta)))"
        }
        DispatchQueue.global().async {
            if let appleScript = NSAppleScript(source: scriptText) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
    }
    
    private func toggleSystemMute() {
        let scriptText = "set volume output muted (not (output muted of (get volume settings)))"
        DispatchQueue.global().async {
            if let appleScript = NSAppleScript(source: scriptText) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
    }
    
    // MARK: - Modifiers Parsing
    
    private func parseModifiers(_ modifiers: [String]?) -> CGEventFlags {
        guard let list = modifiers else { return [] }
        var flags = CGEventFlags()
        for mod in list {
            switch mod.lowercased() {
            case "command", "cmd":
                flags.insert(.maskCommand)
            case "option", "alt":
                flags.insert(.maskAlternate)
            case "shift":
                flags.insert(.maskShift)
            case "control", "ctrl":
                flags.insert(.maskControl)
            default:
                break
            }
        }
        return flags
    }
}
