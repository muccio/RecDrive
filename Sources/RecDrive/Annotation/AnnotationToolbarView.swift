import SwiftUI
import AppKit

/// Floating HUD toolbar rendered on top of the annotation canvas.
/// Offers quick tool switches, color pickers, stroke widths, and actions.
public struct AnnotationToolbarView: View {
    @ObservedObject var manager = AnnotationManager.shared
    
    private let presetWidths: [(label: String, width: CGFloat, dotSize: CGFloat)] = [
        ("Sottile", 3.0, 5.0),
        ("Medio", 6.0, 9.0),
        ("Spesso", 12.0, 14.0)
    ]
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 8) {
            // Drag Grip Indicator
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 11, weight: .bold))
                .padding(.leading, 6)
                .help("Trascina per spostare la barra")
            
            if manager.isToolbarCollapsed {
                collapsedView
            } else {
                expandedView
            }
            
            // Collapse / Expand Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    manager.isToolbarCollapsed.toggle()
                }
            } label: {
                Image(systemName: manager.isToolbarCollapsed ? "chevron.right" : "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help(manager.isToolbarCollapsed ? "Espandi barra" : "Riduci barra")
            .padding(.trailing, 4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        .frame(height: 44)
    }
    
    // MARK: - Expanded Toolbar Content
    
    private var expandedView: some View {
        HStack(spacing: 8) {
            // 1. Tool Selectors
            HStack(spacing: 3) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button {
                        if tool == .text {
                            manager.currentTool = .text
                            manager.openTextBoxAtMouseLocation()
                        } else {
                            manager.currentTool = tool
                        }
                    } label: {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(manager.currentTool == tool ? .white : .primary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(manager.currentTool == tool ? Color.accentColor : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(tool == .text ? "Testo (T)" : tool.title)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            
            Divider()
                .frame(height: 20)
            
            // 2. Color Palette (Visible for Pen and Highlighter)
            if manager.currentTool != .eraser {
                HStack(spacing: 6) {
                    ForEach(AnnotationColor.presets) { preset in
                        Button {
                            manager.currentColor = preset.color
                        } label: {
                            Circle()
                                .fill(Color(nsColor: preset.color))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .opacity(manager.currentColor == preset.color ? 1 : 0)
                                )
                                .shadow(radius: manager.currentColor == preset.color ? 1 : 0)
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                }
                
                Divider()
                    .frame(height: 20)
                
                // 3. Stroke Widths
                HStack(spacing: 6) {
                    ForEach(presetWidths, id: \.label) { item in
                        Button {
                            manager.currentStrokeWidth = item.width
                        } label: {
                            Circle()
                                .fill(manager.currentStrokeWidth == item.width ? Color.primary : Color.secondary.opacity(0.5))
                                .frame(width: item.dotSize, height: item.dotSize)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(item.label)
                    }
                }
                
                Divider()
                    .frame(height: 20)
            }
            
            // 4. Quick Actions
            HStack(spacing: 4) {
                // Undo
                Button {
                    manager.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                        .frame(width: 26, height: 26)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .help("Annulla (⌘Z)")
                
                // Clear All
                Button {
                    manager.clearAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .frame(width: 26, height: 26)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .help("Pulisci tutto (C)")
                
                // Close / Terminate Annotation
                Button {
                    manager.stopAnnotation()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.red.opacity(0.85))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Chiudi annotazione (Esc)")
            }
        }
    }
    
    // MARK: - Collapsed View
    
    private var collapsedView: some View {
        HStack(spacing: 6) {
            Image(systemName: manager.currentTool.systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.accentColor)
            Text(manager.currentTool.title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
    }
}
