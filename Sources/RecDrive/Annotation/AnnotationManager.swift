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
    
    // MARK: - Pass-through Updates
    
    private func updateToolPassThrough() {
        let isPointer = (currentTool == .pointer)
        for window in overlayWindows {
            window.updateMouseEventsPassThrough(isPointer: isPointer)
        }
    }
}
