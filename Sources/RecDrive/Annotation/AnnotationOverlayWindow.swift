import AppKit

/// Full-screen transparent overlay window hosting the annotation canvas.
public final class AnnotationOverlayWindow: NSWindow {
    public let canvasView: AnnotationCanvasView
    
    public init(screen: NSScreen) {
        self.canvasView = AnnotationCanvasView(frame: NSRect(origin: .zero, size: screen.frame.size))
        
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false
        
        self.contentView = canvasView
    }
    
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
    
    public func updateMouseEventsPassThrough(isPointer: Bool) {
        self.ignoresMouseEvents = isPointer
        if isPointer {
            self.orderBack(nil)
        } else {
            self.makeKeyAndOrderFront(nil)
        }
        self.invalidateCursorRects(for: canvasView)
    }
}
