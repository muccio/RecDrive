import AppKit
import Foundation

/// Bridge adapter mapping incoming PencilDrawEvents from the iPad Companion
/// into native drawing actions on RecDrive's AnnotationCanvasView overlay.
/// Injects strokes directly into the AppKit view hierarchy without altering
/// or moving the macOS system mouse cursor.
@MainActor
public final class RecDriveOverlayAdapter {
    public static let shared = RecDriveOverlayAdapter()
    
    private init() {}
    
    /// Processes an incoming drawing event from the iPad.
    public func handlePencilEvent(_ event: PencilDrawEvent) {
        // Global canvas operations
        switch event.phase {
        case .clearAll:
            AnnotationManager.shared.clearAll()
            return
        case .undo:
            AnnotationManager.shared.undo()
            return
        case .began, .moved, .ended, .cancelled:
            break
        }
        
        // 1. Ensure annotation overlay is visible and active on screen
        if !AnnotationManager.shared.isAnnotationActive {
            AnnotationManager.shared.startAnnotation()
        }
        
        // 2. Locate active AnnotationCanvasView
        guard let canvasView = findActiveCanvasView() else {
            print("[RecDriveOverlayAdapter] No active AnnotationCanvasView found")
            return
        }
        
        // 3. Configure tool parameters (pen, eraser, color, width)
        if event.isEraser {
            AnnotationManager.shared.currentTool = .eraser
        } else {
            AnnotationManager.shared.currentTool = .pen
            if let color = NSColor(hexString: event.colorHex) {
                AnnotationManager.shared.currentColor = color
            }
            AnnotationManager.shared.currentStrokeWidth = CGFloat(event.lineWidth)
        }
        
        // 4. Calculate view coordinates from normalized iPad coordinates
        // AnnotationCanvasView uses isFlipped = true (origin at top-left)
        let bounds = canvasView.bounds
        let targetX = max(0.0, min(bounds.width, CGFloat(event.normalizedX) * bounds.width))
        let targetY: CGFloat = canvasView.isFlipped
            ? max(0.0, min(bounds.height, CGFloat(event.normalizedY) * bounds.height))
            : max(0.0, min(bounds.height, (1.0 - CGFloat(event.normalizedY)) * bounds.height))
        let targetPoint = CGPoint(x: targetX, y: targetY)
        
        // 5. Dispatch synthetic NSEvent directly to the canvas view without moving mouse cursor
        guard let window = canvasView.window else { return }
        let windowLocation = canvasView.convert(targetPoint, to: nil)
        
        let eventType: NSEvent.EventType
        switch event.phase {
        case .began:
            eventType = .leftMouseDown
        case .moved:
            eventType = .leftMouseDragged
        case .ended, .cancelled:
            eventType = .leftMouseUp
        default:
            return
        }
        
        guard let syntheticEvent = NSEvent.mouseEvent(
            with: eventType,
            location: windowLocation,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: Float(max(0.1, min(1.0, event.force)))
        ) else { return }
        
        switch event.phase {
        case .began:
            canvasView.mouseDown(with: syntheticEvent)
        case .moved:
            canvasView.mouseDragged(with: syntheticEvent)
        case .ended, .cancelled:
            canvasView.mouseUp(with: syntheticEvent)
        default:
            break
        }
    }
    
    // MARK: - Window & Canvas Discovery
    
    private func findActiveCanvasView() -> AnnotationCanvasView? {
        // Search through visible application windows for AnnotationOverlayWindow or AnnotationCanvasView
        for window in NSApp.windows {
            if let overlayWindow = window as? AnnotationOverlayWindow {
                return overlayWindow.canvasView
            }
            if let canvas = window.contentView as? AnnotationCanvasView {
                return canvas
            }
        }
        return nil
    }
}

// MARK: - Hex Color Parsing Extension

extension NSColor {
    /// Initializes an NSColor from a hex string (e.g. "#FF3B30", "FF3B30", "#FF3B30FF").
    convenience init?(hexString: String) {
        var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 6 || clean.count == 8 else { return nil }
        
        var value: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&value) else { return nil }
        
        let r, g, b, a: CGFloat
        if clean.count == 6 {
            r = CGFloat((value & 0xFF0000) >> 16) / 255.0
            g = CGFloat((value & 0x00FF00) >> 8) / 255.0
            b = CGFloat(value & 0x0000FF) / 255.0
            a = 1.0
        } else {
            r = CGFloat((value & 0xFF000000) >> 24) / 255.0
            g = CGFloat((value & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((value & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(value & 0x000000FF) / 255.0
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
