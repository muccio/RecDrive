import AppKit

/// Tools available during live screen drawing.
public enum AnnotationTool: String, CaseIterable, Identifiable, Sendable {
    case pointer      // Pass-through cursor to interact with apps beneath
    case pen          // Freehand solid opaque pen
    case highlighter  // Translucent highlighter
    case eraser       // Stroke eraser
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .pointer: return "Cursore"
        case .pen: return "Penna"
        case .highlighter: return "Evidenziatore"
        case .eraser: return "Gomma"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .pointer: return "cursorarrow"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser.fill"
        }
    }
}

/// Color presets available in the drawing HUD.
public struct AnnotationColor: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let color: NSColor
    
    public static let red = AnnotationColor(id: "red", name: "Rosso", color: .systemRed)
    public static let yellow = AnnotationColor(id: "yellow", name: "Giallo", color: .systemYellow)
    public static let green = AnnotationColor(id: "green", name: "Verde", color: .systemGreen)
    public static let blue = AnnotationColor(id: "blue", name: "Blu", color: .systemBlue)
    public static let white = AnnotationColor(id: "white", name: "Bianco", color: .white)
    public static let black = AnnotationColor(id: "black", name: "Nero", color: .black)
    
    public static let presets: [AnnotationColor] = [
        .red, .yellow, .green, .blue, .white, .black
    ]
}

/// Model representing a single drawn stroke on the screen canvas.
public final class AnnotationStroke: Identifiable {
    public let id: UUID
    public var path: NSBezierPath
    public var points: [CGPoint]
    public var color: NSColor
    public var width: CGFloat
    public var isHighlighter: Bool
    
    public init(
        id: UUID = UUID(),
        path: NSBezierPath,
        points: [CGPoint],
        color: NSColor,
        width: CGFloat,
        isHighlighter: Bool
    ) {
        self.id = id
        self.path = path
        self.points = points
        self.color = color
        self.width = width
        self.isHighlighter = isHighlighter
    }
    
    /// Checks if a touch/mouse point is within a threshold distance of any stroke point.
    public func contains(point: CGPoint, threshold: CGFloat) -> Bool {
        let radiusSquared = threshold * threshold
        for pt in points {
            let dx = pt.x - point.x
            let dy = pt.y - point.y
            if dx * dx + dy * dy <= radiusSquared {
                return true
            }
        }
        return false
    }
    
    /// Renders the stroke into the current graphics context.
    public func draw(in context: CGContext) {
        context.saveGState()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        
        if isHighlighter {
            color.withAlphaComponent(0.42).setStroke()
        } else {
            color.setStroke()
        }
        path.stroke()
        context.restoreGState()
    }
}
