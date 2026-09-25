import AppKit

/// Unified history snapshot capturing both drawn strokes and text annotations.
private struct CanvasHistoryState {
    let strokes: [AnnotationStroke]
    let texts: [AnnotationText]
}

/// High-performance transparent drawing canvas rendered over the desktop.
/// Captures mouse events, interpolates smooth quadratic bezier curves, renders freehand strokes,
/// and allows inserting and editing text boxes directly on screen.
public final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    public private(set) var strokes: [AnnotationStroke] = []
    public private(set) var texts: [AnnotationText] = []
    
    private var currentStroke: AnnotationStroke?
    private var previousPoint: CGPoint = .zero
    
    private var undoStack: [CanvasHistoryState] = []
    private var redoStack: [CanvasHistoryState] = []
    
    // Active on-screen inline text box editor
    private var activeTextField: NSTextField?
    private var activeFontSize: CGFloat = 26.0
    
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
        
        // 1. Render all committed strokes
        for stroke in strokes {
            stroke.draw(in: context)
        }
        
        // 2. Render all committed text annotations
        for textItem in texts {
            textItem.draw(in: context)
        }
        
        // 3. Render active stroke currently being drawn
        currentStroke?.draw(in: context)
    }
    
    // MARK: - Mouse Event Handling
    
    public override func mouseDown(with event: NSEvent) {
        let tool = AnnotationManager.shared.currentTool
        guard tool != .pointer else { return }
        
        let point = convert(event.locationInWindow, from: nil)
        
        // If an active text field exists, check if user clicked outside
        if let activeField = activeTextField {
            let pointInField = activeField.convert(event.locationInWindow, from: nil)
            if !activeField.bounds.contains(pointInField) {
                commitActiveTextBox()
            } else {
                return
            }
        }
        
        if tool == .text {
            openTextBox(at: point)
            return
        }
        
        if tool == .eraser {
            eraseItems(near: point)
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
        guard tool != .pointer, tool != .text else { return }
        
        let currentPoint = convert(event.locationInWindow, from: nil)
        
        if tool == .eraser {
            eraseItems(near: currentPoint)
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
        guard tool != .pointer, tool != .text else { return }
        
        if tool == .eraser {
            return
        }
        
        guard let stroke = currentStroke else { return }
        
        let currentPoint = convert(event.locationInWindow, from: nil)
        stroke.path.line(to: currentPoint)
        stroke.points.append(currentPoint)
        
        saveSnapshot()
        strokes.append(stroke)
        currentStroke = nil
        
        setNeedsDisplay(bounds)
    }
    
    // MARK: - Text Tool Handling
    
    /// Opens an inline text editor box at the current mouse cursor location on screen.
    public func openTextBoxAtCurrentMousePosition() {
        guard let window = self.window else { return }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = convert(windowPoint, from: nil)
        openTextBox(at: viewPoint)
    }
    
    /// Opens an inline text editor box at a specific coordinate.
    public func openTextBox(at point: CGPoint) {
        commitActiveTextBox()
        
        // Scale font size based on selected stroke width
        let fontSize: CGFloat
        switch AnnotationManager.shared.currentStrokeWidth {
        case ..<4.5: fontSize = 20.0
        case 4.5..<9.0: fontSize = 28.0
        default: fontSize = 38.0
        }
        
        let initialWidth: CGFloat = 280
        let initialHeight: CGFloat = fontSize + 16
        
        // Clamp frame within visible bounds
        let clampedX = min(max(10, point.x), max(10, bounds.width - initialWidth - 20))
        let clampedY = min(max(10, point.y), max(10, bounds.height - initialHeight - 20))
        let frame = NSRect(x: clampedX, y: clampedY, width: initialWidth, height: initialHeight)
        
        let tf = NSTextField(frame: frame)
        tf.isBordered = false
        tf.drawsBackground = true
        tf.backgroundColor = NSColor.black.withAlphaComponent(0.45)
        tf.wantsLayer = true
        tf.layer?.cornerRadius = 6
        tf.layer?.borderWidth = 1.5
        tf.layer?.borderColor = AnnotationManager.shared.currentColor.cgColor
        tf.font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        tf.textColor = AnnotationManager.shared.currentColor
        tf.placeholderString = "Scrivi testo qui..."
        tf.focusRingType = .none
        tf.delegate = self
        
        addSubview(tf)
        self.activeTextField = tf
        self.activeFontSize = fontSize
        
        window?.makeFirstResponder(tf)
    }
    
    /// Commits the active text box content to the canvas and removes the text field.
    public func commitActiveTextBox() {
        guard let tf = activeTextField else { return }
        let trimmed = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            saveSnapshot()
            let item = AnnotationText(
                text: trimmed,
                origin: CGPoint(x: tf.frame.origin.x + 4, y: tf.frame.origin.y + 4),
                color: AnnotationManager.shared.currentColor,
                fontSize: activeFontSize
            )
            texts.append(item)
        }
        tf.removeFromSuperview()
        self.activeTextField = nil
        setNeedsDisplay(bounds)
        window?.makeFirstResponder(self)
    }
    
    // MARK: - NSTextFieldDelegate for Text Box
    
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Return pressed: commit text
            commitActiveTextBox()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Esc pressed: dismiss/commit
            commitActiveTextBox()
            return true
        }
        return false
    }
    
    public func controlTextDidChange(_ obj: Notification) {
        guard let tf = activeTextField else { return }
        let text = tf.stringValue.isEmpty ? (tf.placeholderString ?? "") : tf.stringValue
        let size = (text as NSString).size(withAttributes: [.font: tf.font!])
        let newWidth = max(240, min(size.width + 30, bounds.width - tf.frame.origin.x - 20))
        tf.frame.size.width = newWidth
    }
    
    // MARK: - Eraser Logic
    
    private func eraseItems(near point: CGPoint) {
        let threshold: CGFloat = 18.0
        let originalStrokeCount = strokes.count
        let originalTextCount = texts.count
        
        let remainingStrokes = strokes.filter { !$0.contains(point: point, threshold: threshold) }
        let remainingTexts = texts.filter { !$0.contains(point: point, threshold: threshold) }
        
        if remainingStrokes.count != originalStrokeCount || remainingTexts.count != originalTextCount {
            saveSnapshot()
            strokes = remainingStrokes
            texts = remainingTexts
            setNeedsDisplay(bounds)
        }
    }
    
    // MARK: - Undo, Redo & Clear Actions
    
    private func saveSnapshot() {
        undoStack.append(CanvasHistoryState(strokes: strokes, texts: texts))
        redoStack.removeAll()
    }
    
    public func undo() {
        commitActiveTextBox()
        if let previous = undoStack.popLast() {
            redoStack.append(CanvasHistoryState(strokes: strokes, texts: texts))
            strokes = previous.strokes
            texts = previous.texts
            setNeedsDisplay(bounds)
        } else if !strokes.isEmpty || !texts.isEmpty {
            redoStack.append(CanvasHistoryState(strokes: strokes, texts: texts))
            strokes.removeAll()
            texts.removeAll()
            setNeedsDisplay(bounds)
        }
    }
    
    public func redo() {
        commitActiveTextBox()
        if let next = redoStack.popLast() {
            undoStack.append(CanvasHistoryState(strokes: strokes, texts: texts))
            strokes = next.strokes
            texts = next.texts
            setNeedsDisplay(bounds)
        }
    }
    
    public func clearAll() {
        commitActiveTextBox()
        guard !strokes.isEmpty || !texts.isEmpty || currentStroke != nil else { return }
        saveSnapshot()
        strokes.removeAll()
        texts.removeAll()
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
        case .text:
            cursor = .iBeam
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
            commitActiveTextBox()
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
        case "t":
            AnnotationManager.shared.currentTool = .text
            openTextBoxAtCurrentMousePosition()
        case "p":
            commitActiveTextBox()
            AnnotationManager.shared.currentTool = .pen
        case "h":
            commitActiveTextBox()
            AnnotationManager.shared.currentTool = .highlighter
        case "e":
            commitActiveTextBox()
            AnnotationManager.shared.currentTool = .eraser
        case "v", "a":
            commitActiveTextBox()
            AnnotationManager.shared.currentTool = .pointer
        case "c":
            clearAll()
        default:
            super.keyDown(with: event)
        }
    }
}
