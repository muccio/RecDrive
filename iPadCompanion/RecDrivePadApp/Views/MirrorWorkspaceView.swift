import SwiftUI

/// Main workspace view for the iPad Companion app.
/// Computes the exact aspect-fit rectangle of the incoming Mac video stream
/// and superimposes the PencilCanvasView with 1:1 pixel alignment.
/// Hosts the compact floating HUD toolbar for live drawing and Apple Pencil control.
public struct MirrorWorkspaceView: View {
    @ObservedObject var network = MacConnectionClient.shared
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var currentColorHex: String = "#FF3B30"
    @State private var currentLineWidth: Double = 6.0
    @State private var isEraser: Bool = false
    @State private var allowFingerDrawing: Bool = false
    @State private var isHUDVisible: Bool = true
    
    @State private var showingManualIPAlert: Bool = false
    @State private var manualIPText: String = ""
    @AppStorage("savedManualIP") private var savedManualIP: String = ""
    
    private let colorPresets: [(name: String, hex: String, color: Color)] = [
        ("Rosso", "#FF3B30", .red),
        ("Giallo", "#FFCC00", .yellow),
        ("Verde", "#34C759", .green),
        ("Blu", "#007AFF", .blue),
        ("Bianco", "#FFFFFF", .white),
        ("Nero", "#000000", .black)
    ]
    
    private let strokeSizes: [Double] = [3.0, 6.0, 12.0, 24.0]
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { proxy in
                let containerSize = proxy.size
                
                if let frame = network.currentFrame {
                    let imageRect = aspectFitRect(for: frame.size, in: containerSize)
                    
                    ZStack {
                        // 1. Live Screen Mirroring Image
                        Image(uiImage: frame)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: imageRect.width, height: imageRect.height)
                        
                        // 2. 1:1 Pixel-Matched Apple Pencil Drawing Canvas
                        PencilCanvasView(
                            currentColorHex: $currentColorHex,
                            currentLineWidth: $currentLineWidth,
                            isEraser: $isEraser,
                            allowFingerDrawing: allowFingerDrawing
                        ) { event in
                            network.sendPencilEvent(event)
                        }
                        .frame(width: imageRect.width, height: imageRect.height)
                    }
                    .position(x: imageRect.midX, y: imageRect.midY)
                } else {
                    waitingStateView
                }
            }
            
            // 3. Compact Floating HUD Toolbar
            VStack {
                if isHUDVisible {
                    floatingToolbarHUD
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 10)
            .padding(.horizontal, 16)
        }
        .onAppear {
            network.startBrowsing()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                network.handleAppDidBecomeActive()
            case .background:
                network.handleAppDidEnterBackground()
            default:
                break
            }
        }
        .alert("Connetti a Mac tramite IP", isPresented: $showingManualIPAlert) {
            TextField("es. 192.168.1.50", text: $manualIPText)
                .keyboardType(.numbersAndPunctuation)
                .autocapitalization(.none)
            Button("Annulla", role: .cancel) {}
            Button("Connetti") {
                savedManualIP = manualIPText
                network.connectToHost(manualIPText)
            }
        } message: {
            Text("Inserisci l'indirizzo IP locale del tuo Mac per stabilire una connessione diretta:")
        }
    }
    
    // MARK: - Aspect-Fit Math
    
    private func aspectFitRect(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let originX = (containerSize.width - width) / 2.0
        let originY = (containerSize.height - height) / 2.0
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
    
    // MARK: - Waiting State View
    
    private var waitingStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "display.and.ipad")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.white.opacity(0.8))
            
            VStack(spacing: 8) {
                Text("RecDrive Pad")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(network.connectionStatus)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 32)
            }
            
            if !network.isConnected {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .red))
                    .scaleEffect(1.2)
                    .padding(.top, 4)
                
                HStack(spacing: 12) {
                    Button(action: { network.restartBrowsing() }) {
                        Label("Riprova Ricerca", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.15))
                            .foregroundColor(.white)
                            .cornerRadius(18)
                    }
                    
                    Button(action: {
                        manualIPText = savedManualIP.isEmpty ? "192.168.1." : savedManualIP
                        showingManualIPAlert = true
                    }) {
                        Label("Inserisci IP Mac", systemImage: "network")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(18)
                    }
                }
                .padding(.top, 8)
                
                Text("Assicurati che RecDrive sia aperto sul Mac e collegato alla stessa rete Wi-Fi o tramite cavo USB.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: 400)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Floating HUD Toolbar
    
    private var floatingToolbarHUD: some View {
        HStack(spacing: 14) {
            // Connection Status Pill
            Button(action: {
                if !network.isConnected {
                    network.reconnect()
                }
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(network.isConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(network.isConnected ? "RecDrive Mac" : "Riconnetti...")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(network.isConnected ? 0.12 : 0.22))
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.2))
            
            // Tools: Pen vs Eraser
            HStack(spacing: 6) {
                Button(action: { isEraser = false }) {
                    Image(systemName: "pencil.tip")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(!isEraser ? .white : .white.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(!isEraser ? Color.red : Color.clear)
                        .clipShape(Circle())
                }
                
                Button(action: { isEraser = true }) {
                    Image(systemName: "eraser.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isEraser ? .white : .white.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(isEraser ? Color.white.opacity(0.3) : Color.clear)
                        .clipShape(Circle())
                }
            }
            
            if !isEraser {
                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.2))
                
                // Color Palette
                HStack(spacing: 8) {
                    ForEach(colorPresets, id: \.hex) { preset in
                        Button(action: { currentColorHex = preset.hex }) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: currentColorHex == preset.hex ? 2.5 : 0)
                                )
                                .shadow(radius: 2)
                        }
                    }
                }
                
                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.2))
                
                // Line Widths
                HStack(spacing: 6) {
                    ForEach(strokeSizes, id: \.self) { size in
                        Button(action: { currentLineWidth = size }) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: CGFloat(size / 1.5), height: CGFloat(size / 1.5))
                                .frame(width: 24, height: 24)
                                .background(currentLineWidth == size ? Color.white.opacity(0.25) : Color.clear)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.2))
            
            // Actions: Undo & Clear All
            HStack(spacing: 6) {
                Button(action: {
                    let undoEvent = PencilDrawEvent(phase: .undo)
                    network.sendPencilEvent(undoEvent)
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                
                Button(action: {
                    let clearEvent = PencilDrawEvent(phase: .clearAll)
                    network.sendPencilEvent(clearEvent)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.2))
            
            // Toggle Finger Drawing (Finger vs Pencil Only)
            Button(action: { allowFingerDrawing.toggle() }) {
                Image(systemName: allowFingerDrawing ? "hand.draw.fill" : "applepencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(allowFingerDrawing ? .orange : .white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(allowFingerDrawing ? Color.orange.opacity(0.2) : Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(32)
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
    }
}
