import SwiftUI
import UIKit

/// High-performance UIView hosting Apple Pencil touch interception,
/// smooth quadratic bezier rendering for zero-latency local feedback,
/// and normalized event dispatching to the Mac.
public final class PencilTouchUIView: UIView {
    public var onPencilEvent: ((PencilDrawEvent) -> Void)?
    public var activeTool: String = "pen" // "pen", "staff", "eraser"
    public var currentColorHex: String = "#FF3B30"
    public var currentLineWidth: Double = 6.0
    public var isEraser: Bool = false
    public var allowFingerDrawing: Bool = false
    
    private var activePath = UIBezierPath()
    private var previousPoint: CGPoint = .zero
    private let drawingLayer = CAShapeLayer()
    
    // Musical staff ("Pentagramma") Apple Pencil state
    private var staffStartPoint: CGPoint = .zero
    private var isDrawingStaff: Bool = false
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        self.backgroundColor = .clear
        self.isOpaque = false
        self.isMultipleTouchEnabled = false
        self.clipsToBounds = true
        
        drawingLayer.fillColor = UIColor.clear.cgColor
        drawingLayer.lineCap = .round
        drawingLayer.lineJoin = .round
        layer.addSublayer(drawingLayer)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        drawingLayer.frame = bounds
    }
    
    // MARK: - Touch Interception
    
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if !allowFingerDrawing && touch.type != .pencil { return }
        
        let location = touch.location(in: self)
        previousPoint = location
        
        if activeTool == "staff" {
            staffStartPoint = location
            isDrawingStaff = true
            updateStaffLayer(start: location, end: location)
            dispatch(phase: .began, touch: touch, location: location)
            return
        }
        
        // Start local rendering layer for immediate Apple Pencil visual feedback
        activePath.removeAllPoints()
        activePath.move(to: location)
        
        updateLayerProperties()
        drawingLayer.path = activePath.cgPath
        
        dispatch(phase: .began, touch: touch, location: location)
    }
    
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if !allowFingerDrawing && touch.type != .pencil { return }
        
        if activeTool == "staff" {
            let lastTouch = event?.coalescedTouches(for: touch)?.last ?? touch
            let currentLocation = lastTouch.location(in: self)
            updateStaffLayer(start: staffStartPoint, end: currentLocation)
            dispatch(phase: .moved, touch: lastTouch, location: currentLocation)
            return
        }
        
        // Process coalesced touches for maximal 120Hz/240Hz Apple Pencil sampling precision
        let coalescedTouches = event?.coalescedTouches(for: touch) ?? [touch]
        for cTouch in coalescedTouches {
            let currentLocation = cTouch.location(in: self)
            
            // Quadratic bezier interpolation between midpoints
            let midPoint = CGPoint(
                x: (previousPoint.x + currentLocation.x) / 2.0,
                y: (previousPoint.y + currentLocation.y) / 2.0
            )
            activePath.addQuadCurve(to: midPoint, controlPoint: previousPoint)
            previousPoint = currentLocation
            
            dispatch(phase: .moved, touch: cTouch, location: currentLocation)
        }
        
        drawingLayer.path = activePath.cgPath
    }
    
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if !allowFingerDrawing && touch.type != .pencil { return }
        
        let location = touch.location(in: self)
        
        if activeTool == "staff" {
            isDrawingStaff = false
            dispatch(phase: .ended, touch: touch, location: location)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.activePath.removeAllPoints()
                self?.drawingLayer.path = nil
            }
            return
        }
        
        activePath.addLine(to: location)
        drawingLayer.path = activePath.cgPath
        
        dispatch(phase: .ended, touch: touch, location: location)
        
        // Clear local scratch path shortly after transmission
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.activePath.removeAllPoints()
            self?.drawingLayer.path = nil
        }
    }
    
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if !allowFingerDrawing && touch.type != .pencil { return }
        
        let location = touch.location(in: self)
        isDrawingStaff = false
        dispatch(phase: .cancelled, touch: touch, location: location)
        
        activePath.removeAllPoints()
        drawingLayer.path = nil
    }
    
    // MARK: - Normalization & Event Dispatch
    
    private func dispatch(phase: PencilPhase, touch: UITouch, location: CGPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        let normalizedX = max(0.0, min(1.0, Double(location.x / bounds.width)))
        let normalizedY = max(0.0, min(1.0, Double(location.y / bounds.height)))
        let maxForce = touch.maximumPossibleForce > 0 ? touch.maximumPossibleForce : 1.0
        let force = Double(touch.force / maxForce)
        
        let isEraserActive = (activeTool == "eraser" || isEraser)
        let event = PencilDrawEvent(
            phase: phase,
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            force: max(0.1, min(1.0, force)),
            lineWidth: currentLineWidth,
            colorHex: currentColorHex,
            isEraser: isEraserActive,
            toolName: activeTool
        )
        onPencilEvent?(event)
    }
    
    private func updateStaffLayer(start: CGPoint, end: CGPoint) {
        let leftX = min(start.x, end.x)
        let rightX = max(start.x, end.x)
        let width = rightX - leftX
        guard width > 10 else {
            drawingLayer.path = nil
            return
        }
        
        let rawHeight = abs(end.y - start.y)
        let topY: CGFloat
        let staffHeight: CGFloat
        
        if rawHeight < 20 {
            staffHeight = 44.0
            topY = start.y - (staffHeight / 2.0)
        } else {
            topY = min(start.y, end.y)
            staffHeight = rawHeight
        }
        
        let spacing = staffHeight / 4.0
        let bottomY = topY + staffHeight
        
        let path = UIBezierPath()
        
        // 5 horizontal staff lines
        for i in 0..<5 {
            let y = topY + CGFloat(i) * spacing
            path.move(to: CGPoint(x: leftX, y: y))
            path.addLine(to: CGPoint(x: rightX, y: y))
        }
        
        // Left barline
        path.move(to: CGPoint(x: leftX, y: topY))
        path.addLine(to: CGPoint(x: leftX, y: bottomY))
        
        // Right barline
        path.move(to: CGPoint(x: rightX, y: topY))
        path.addLine(to: CGPoint(x: rightX, y: bottomY))
        
        let uiColor = UIColor(hexString: currentColorHex) ?? .systemRed
        drawingLayer.strokeColor = uiColor.cgColor
        drawingLayer.lineWidth = CGFloat(max(1.5, min(currentLineWidth, 3.5)))
        drawingLayer.path = path.cgPath
    }
    
    private func updateLayerProperties() {
        if isEraser {
            drawingLayer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
            drawingLayer.lineWidth = CGFloat(currentLineWidth * 1.5)
        } else {
            let uiColor = UIColor(hexString: currentColorHex) ?? .systemRed
            drawingLayer.strokeColor = uiColor.cgColor
            drawingLayer.lineWidth = CGFloat(currentLineWidth)
        }
    }
}

/// SwiftUI wrapper for PencilTouchUIView.
public struct PencilCanvasView: UIViewRepresentable {
    @Binding public var activeTool: String
    @Binding public var currentColorHex: String
    @Binding public var currentLineWidth: Double
    @Binding public var isEraser: Bool
    public var allowFingerDrawing: Bool
    public var onPencilEvent: (PencilDrawEvent) -> Void
    
    public init(
        activeTool: Binding<String>,
        currentColorHex: Binding<String>,
        currentLineWidth: Binding<Double>,
        isEraser: Binding<Bool>,
        allowFingerDrawing: Bool = false,
        onPencilEvent: @escaping (PencilDrawEvent) -> Void
    ) {
        self._activeTool = activeTool
        self._currentColorHex = currentColorHex
        self._currentLineWidth = currentLineWidth
        self._isEraser = isEraser
        self.allowFingerDrawing = allowFingerDrawing
        self.onPencilEvent = onPencilEvent
    }
    
    public func makeUIView(context: Context) -> PencilTouchUIView {
        let view = PencilTouchUIView()
        view.activeTool = activeTool
        view.currentColorHex = currentColorHex
        view.currentLineWidth = currentLineWidth
        view.isEraser = isEraser
        view.allowFingerDrawing = allowFingerDrawing
        view.onPencilEvent = onPencilEvent
        return view
    }
    
    public func updateUIView(_ uiView: PencilTouchUIView, context: Context) {
        uiView.activeTool = activeTool
        uiView.currentColorHex = currentColorHex
        uiView.currentLineWidth = currentLineWidth
        uiView.isEraser = isEraser
        uiView.allowFingerDrawing = allowFingerDrawing
        uiView.onPencilEvent = onPencilEvent
    }
}

// MARK: - UIColor Hex Extension

extension UIColor {
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
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
