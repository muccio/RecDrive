import AppKit
import SwiftUI
import Combine

/// Central coordinator for the live screen drawing subsystem.
/// Manages overlay canvas windows, floating toolbar HUD, active tool, color, and stroke settings.
@MainActor
public final class AnnotationManager: ObservableObject {
    public static let shared = AnnotationManager()
    
    @Published public private(set) var isAnnotationActive: Bool = false
    
    @Published public var currentTool: AnnotationTool = .pen {
        didSet {
            updateToolPassThrough()
        }
    }
    
    @Published public var currentColor: NSColor = .systemRed
    @Published public var currentStrokeWidth: CGFloat = 6.0
    @Published public var isToolbarCollapsed: Bool = false
    
    // MARK: - Whiteboard ("Lavagna") Subsystem
    @Published public var isWhiteboardActive: Bool = false {
        didSet {
            handleWhiteboardStateChange()
        }
    }
    
    @Published public var isWhiteboardGridEnabled: Bool = false {
        didSet {
            refreshOverlays()
        }
    }
    
    @Published public var whiteboardGridSpacing: CGFloat = 40.0 {
        didSet {
            refreshOverlays()
        }
    }
    
    private var overlayWindows: [AnnotationOverlayWindow] = []
    private var toolbarPanel: AnnotationToolbarPanel?
    
    public init() {}
    
    // MARK: - Toggle & Lifecycle
    
    public func toggleAnnotation() {
        if isAnnotationActive {
            stopAnnotation()
        } else {
            startAnnotation()
        }
    }
    
    public func startAnnotation() {
        guard !isAnnotationActive else { return }
        
        // Close menu bar popover to free up screen interaction
        StatusItemController.shared.closePopover()
        
        self.isAnnotationActive = true
        self.currentTool = .pen
        
        // 1. Create transparent canvas overlays across all connected displays
        overlayWindows.removeAll()
        for screen in NSScreen.screens {
            let window = AnnotationOverlayWindow(screen: screen)
            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }
        
        // 2. Position floating toolbar on the primary/mouse screen
        let targetScreen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let panel = AnnotationToolbarPanel(screen: targetScreen)
        panel.orderFront(nil)
        self.toolbarPanel = panel
        
        updateToolPassThrough()
    }
    
    public func stopAnnotation() {
        guard isAnnotationActive else { return }
        
        self.isAnnotationActive = false
        self.isWhiteboardActive = false
        self.isWhiteboardGridEnabled = false
        
        // Dismiss toolbar panel
        toolbarPanel?.orderOut(nil)
        toolbarPanel?.close()
        toolbarPanel = nil
        
        // Dismiss overlay canvas windows
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
    }
    
    // MARK: - Actions
    
    public func clearAll() {
        for window in overlayWindows {
            window.canvasView.clearAll()
        }
    }
    
    public func undo() {
        for window in overlayWindows {
            window.canvasView.undo()
        }
    }
    
    public func redo() {
        for window in overlayWindows {
            window.canvasView.redo()
        }
    }
    
    public func openTextBoxAtMouseLocation() {
        guard isAnnotationActive else { return }
        currentTool = .text
        let mouseLocation = NSEvent.mouseLocation
        for window in overlayWindows {
            if window.frame.contains(mouseLocation) {
                window.makeKeyAndOrderFront(nil)
                window.canvasView.openTextBoxAtCurrentMousePosition()
                return
            }
        }
        overlayWindows.first?.canvasView.openTextBoxAtCurrentMousePosition()
    }
    
    // MARK: - Whiteboard Actions & Updates
    
    public func toggleWhiteboard() {
        isWhiteboardActive.toggle()
    }
    
    public func toggleWhiteboardGrid() {
        if !isWhiteboardActive {
            isWhiteboardActive = true
            isWhiteboardGridEnabled = true
        } else {
            isWhiteboardGridEnabled.toggle()
        }
        refreshOverlays()
    }
    
    public func setWhiteboardGridSpacing(_ spacing: CGFloat) {
        whiteboardGridSpacing = max(15.0, min(120.0, spacing))
    }
    
    public func stepGridSpacing(delta: CGFloat) {
        let newSpacing = max(15.0, min(120.0, whiteboardGridSpacing + delta))
        whiteboardGridSpacing = newSpacing
    }
    
    public func refreshOverlays() {
        for window in overlayWindows {
            window.updateMouseEventsPassThrough(isPointer: currentTool == .pointer)
            window.canvasView.setNeedsDisplay(window.canvasView.bounds)
        }
    }
    
    private func handleWhiteboardStateChange() {
        if isWhiteboardActive {
            // When switching to whiteboard, if current color is white, switch to black for readability
            if currentColor == .white {
                currentColor = .black
            }
        }
        refreshOverlays()
    }
    
    // MARK: - Pass-through Updates
    
    private func updateToolPassThrough() {
        let isPointer = (currentTool == .pointer)
        for window in overlayWindows {
            window.updateMouseEventsPassThrough(isPointer: isPointer)
        }
    }
}
