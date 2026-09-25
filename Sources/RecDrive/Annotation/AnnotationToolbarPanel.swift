import AppKit
import SwiftUI

/// Floating, draggable panel hosting the AnnotationToolbarView.
/// Always floats above the canvas overlay window.
public final class AnnotationToolbarPanel: NSPanel {
    public init(screen: NSScreen) {
        let panelWidth: CGFloat = 460
        let panelHeight: CGFloat = 48
        
        let x = screen.frame.origin.x + (screen.frame.width - panelWidth) / 2.0
        let y = screen.frame.origin.y + 60.0
        
        let contentRect = NSRect(
            x: x,
            y: y,
            width: panelWidth,
            height: panelHeight
        )
        
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 2)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.isFloatingPanel = true
        self.isReleasedWhenClosed = false
        
        let hostingView = NSHostingView(rootView: AnnotationToolbarView())
        self.contentView = hostingView
    }
    
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
