import Foundation
import ScreenCaptureKit
import AppKit

// MARK: - Capture Targets

public enum CaptureTarget: Equatable {
    case display(SCDisplay)
    case window(SCWindow)
    
    public static func == (lhs: CaptureTarget, rhs: CaptureTarget) -> Bool {
        switch (lhs, rhs) {
        case (.display(let d1), .display(let d2)):
            return d1.displayID == d2.displayID
        case (.window(let w1), .window(let w2)):
            return w1.windowID == w2.windowID
        default:
            return false
        }
    }
}

public struct DisplayItem: Identifiable, Hashable {
    public let id: CGDirectDisplayID
    public let name: String
    public let width: Int
    public let height: Int
    public let scDisplay: SCDisplay
    
    public init(display: SCDisplay, index: Int) {
        self.id = display.displayID
        self.name = "Display \(index + 1) (\(display.width)x\(display.height))"
        self.width = display.width
        self.height = display.height
        self.scDisplay = display
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: DisplayItem, rhs: DisplayItem) -> Bool {
        lhs.id == rhs.id
    }
}

public struct WindowItem: Identifiable, Hashable {
    public let id: CGWindowID
    public let title: String
    public let appName: String
    public let bundleIdentifier: String?
    public let frame: CGRect
    public let scWindow: SCWindow
    
    public init(window: SCWindow) {
        self.id = window.windowID
        self.title = (window.title?.isEmpty == false) ? window.title! : "Untitled Window"
        self.appName = window.owningApplication?.applicationName ?? "Application"
        self.bundleIdentifier = window.owningApplication?.bundleIdentifier
        self.frame = window.frame
        self.scWindow = window
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Recording State

public enum RecordingState: Equatable {
    case idle
    case preparing
    case recording(elapsed: TimeInterval)
    case finishing
    case failed(String)
}

public struct RecordingMetrics {
    public var duration: TimeInterval = 0
    public var frameCount: Int64 = 0
    public var currentBytesWritten: Int64 = 0
}
