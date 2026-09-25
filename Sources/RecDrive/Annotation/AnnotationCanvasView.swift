import AppKit

/// High-performance transparent drawing canvas rendered over the desktop.
/// Captures mouse events, interpolates smooth quadratic bezier curves, and renders freehand strokes.
public final class AnnotationCanvasView: NSView {
    public private(set) var strokes: [AnnotationStroke] = []
    private var currentStroke: AnnotationStroke?
    private var previousPoint: CGPoint = .zero
    
    private var undoStack: [[AnnotationStroke]] = []
    private var redoStack: [[AnnotationStroke]] = []
    
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    // MARK: - Drawing Cycle
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Render all committed strokes
        for stroke in strokes {
            stroke.draw(in: context)
        }
        
        // Render active stroke currently being drawn
        currentStroke?.draw(in: context)
    }
    
    // MARK: - Mouse Event Handling
    
    public override func mouseDown(with event: NSEvent) {
        let tool = AnnotationManager.shared.currentTool
        guard tool != .pointer else { return }
        
        let point = convert(event.locationInWindow, from: nil)
        
        if tool == .eraser {
            eraseStrokes(near: point)
            return
        }
        
        previousPoint = point
        let path = NSBezierPath()
        path.move(to: point)
        
        let isHighlighter = (tool == .highlighter)
        let strokeColor = AnnotationManager.shared.currentColor
        let strokeWidth = isHighlighter ? (AnnotationManager.shared.currentStrokeWidth * 3.5) : AnnotationManager.shared.currentStrokeWidth
        
        currentStroke = AnnotationStroke(
            path: path,
            points: [point],
            color: strokeColor,
            width: strokeWidth,
            isHighlighter: isHighlighter
        )
        setNeedsDisplay(bounds)
    }
    
    public override func mouseDragged(with event: NSEvent) {
        let tool = AnnotationManager.shared.currentTool
        guard tool != .pointer else { return }
        
        let currentPoint = convert(event.locationInWindow, from: nil)
        
        if tool == .eraser {
            eraseStrokes(near: currentPoint)
            return
        }
        
        guard let stroke = currentStroke else { return }
        
        // Smooth curve interpolation using quadratic bezier midpoint
        let midPoint = CGPoint(
            x: (previousPoint.x + currentPoint.x) / 2.0,
            y: (previousPoint.y + currentPoint.y) / 2.0
        )
        
        stroke.path.curve(to: midPoint, controlPoint1: previousPoint, controlPoint2: previousPoint)
        stroke.points.append(currentPoint)
        previousPoint = currentPoint
        
        setNeedsDisplay(bounds)
    }
    
    public override func mouseUp(with event: NSEvent) {
        let tool = AnnotationManager.shared.currentTool
        guard tool != .pointer else { return }
        
        if tool == .eraser {
            return
        }
        
        guard let stroke = currentStroke else { return }
        
        let currentPoint = convert(event.locationInWindow, from: nil)
        stroke.path.line(to: currentPoint)
        stroke.points.append(currentPoint)
        
        undoStack.append(strokes)
        redoStack.removeAll()
        strokes.append(stroke)
        currentStroke = nil
        
        setNeedsDisplay(bounds)
    }
    
    // MARK: - Eraser Logic
    
    private func eraseStrokes(near point: CGPoint) {
        let threshold: CGFloat = 18.0
        let originalCount = strokes.count
        
        let remaining = strokes.filter { stroke in
            !stroke.contains(point: point, threshold: threshold)
        }
        
        if remaining.count != originalCount {
            undoStack.append(strokes)
            redoStack.removeAll()
            strokes = remaining
            setNeedsDisplay(bounds)
        }
    }
    
    // MARK: - Undo, Redo & Clear Actions
    
    public func undo() {
        if let previous = undoStack.popLast() {
            redoStack.append(strokes)
            strokes = previous
            setNeedsDisplay(bounds)
        } else if !strokes.isEmpty {
            redoStack.append(strokes)
            strokes.removeAll()
            setNeedsDisplay(bounds)
        }
    }
    
    public func redo() {
        if let next = redoStack.popLast() {
            undoStack.append(strokes)
            strokes = next
            setNeedsDisplay(bounds)
        }
    }
    
    public func clearAll() {
        guard !strokes.isEmpty || currentStroke != nil else { return }
        undoStack.append(strokes)
        redoStack.removeAll()
        strokes.removeAll()
        currentStroke = nil
        setNeedsDisplay(bounds)
    }
    
    // MARK: - Cursors
    
    public override func resetCursorRects() {
        super.resetCursorRects()
        let cursor: NSCursor
        switch AnnotationManager.shared.currentTool {
        case .pen, .highlighter:
            cursor = .crosshair
        case .eraser:
            cursor = .crosshair
        case .pointer:
            cursor = .arrow
        }
        addCursorRect(bounds, cursor: cursor)
    }
    
    // MARK: - Keyboard Handling
    
    public override func keyDown(with event: NSEvent) {
        // Esc: Exit drawing mode
        if event.keyCode == 53 {
            AnnotationManager.shared.stopAnnotation()
            return
        }
        
        // Command Combinations
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "z" {
                if event.modifierFlags.contains(.shift) {
                    redo()
                } else {
                    undo()
                }
                return
            } else if event.charactersIgnoringModifiers == "k" {
                clearAll()
                return
            }
        }
        
        // Single Character Tool Shortcuts
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p":
            AnnotationManager.shared.currentTool = .pen
        case "h":
            AnnotationManager.shared.currentTool = .highlighter
        case "e":
            AnnotationManager.shared.currentTool = .eraser
        case "v", "a":
            AnnotationManager.shared.currentTool = .pointer
        case "c":
            clearAll()
        default:
            super.keyDown(with: event)
        }
    }
}
