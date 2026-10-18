import Foundation
import Network

/// Bonjour peer-to-peer TCP server running on the Mac.
/// Advertises the `_recdrive-pad._tcp` service, receives incoming Apple Pencil events from the iPad,
/// dispatches them to RecDriveOverlayAdapter on the MainActor, and streams JPEG video frames back to the iPad.
public final class iPadBridgeServer: @unchecked Sendable {
    public static let shared = iPadBridgeServer()
    public static let serviceType = "_recdrive-pad._tcp"
    
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var receiveBuffer = Data()
    private let queue = DispatchQueue(label: "com.recdrive.ipadbridge.server", qos: .userInteractive)
    
    // Backpressure lock to drop lagging video frames and keep mirroring latency near zero
    private var isSendingFrame = false
    private let sendLock = NSLock()
    
    public var onClientConnected: (@Sendable () -> Void)?
    public var onClientDisconnected: (@Sendable () -> Void)?
    
    private(set) public var isRunning = false
    private(set) public var isClientConnected = false
    
    private init() {}
    
    // MARK: - Lifecycle
    
    /// Starts the Bonjour NWListener for the iPad Companion service.
    public func start(port: NWEndpoint.Port? = nil) {
        guard !isRunning else { return }
        
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            parameters.serviceClass = .interactiveVideo
            
            let targetPort = port ?? NWEndpoint.Port(rawValue: 19842)!
            let listener = try NWListener(using: parameters, on: targetPort)
            listener.service = NWListener.Service(type: Self.serviceType)
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[iPadBridgeServer] Bonjour listener ready on port \(listener.port?.rawValue ?? 0) for \(Self.serviceType)")
                case .failed(let error):
                    print("[iPadBridgeServer] Listener failed: \(error)")
                default:
                    break
                }
            }
            
            listener.start(queue: queue)
            self.listener = listener
            self.isRunning = true
            print("[iPadBridgeServer] Service started: \(Self.serviceType)")
        } catch {
            print("[iPadBridgeServer] Failed to initialize NWListener: \(error)")
        }
    }
    
    /// Stops the server and terminates any active iPad connection.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        
        activeConnection?.cancel()
        activeConnection = nil
        isClientConnected = false
        receiveBuffer.removeAll()
        
        listener?.cancel()
        listener = nil
        print("[iPadBridgeServer] Service stopped")
    }
    
    // MARK: - Video Streaming
    
    /// Transmits a JPEG compressed screen frame to the connected iPad client.
    /// Drops frames if previous transmission is still pending, ensuring low-latency delivery.
    public func sendVideoFrame(_ jpegData: Data) {
        guard isClientConnected, let connection = activeConnection else { return }
        
        sendLock.lock()
        if isSendingFrame {
            sendLock.unlock()
            return
        }
        isSendingFrame = true
        sendLock.unlock()
        
        let packet = CompanionPacket.pack(type: .videoFrame, payload: jpegData)
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            self.sendLock.lock()
            self.isSendingFrame = false
            self.sendLock.unlock()
            
            if let error = error {
                print("[iPadBridgeServer] Error sending frame: \(error)")
            }
        })
    }
    
    // MARK: - Connection Handling
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        queue.async { [weak self, connection] in
            guard let self = self else { return }
            
            // Disconnect any existing peer to allow instant reconnection
            if let existing = self.activeConnection {
                existing.cancel()
                self.activeConnection = nil
            }
            
            self.activeConnection = connection
            
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self = self, let connection = connection else { return }
                switch state {
                case .ready:
                    print("[iPadBridgeServer] iPad client connected: \(connection.endpoint)")
                    self.isClientConnected = true
                    self.receiveBuffer.removeAll()
                    self.onClientConnected?()
                    Task { @MainActor in
                        ScreenMirrorStreamer.shared.startStreaming()
                    }
                    self.receiveNextPacket(from: connection)
                case .failed(let error):
                    print("[iPadBridgeServer] Connection failed: \(error)")
                    self.handleDisconnection(connection: connection)
                case .cancelled:
                    self.handleDisconnection(connection: connection)
                default:
                    break
                }
            }
            
            connection.start(queue: self.queue)
        }
    }
    
    private func receiveNextPacket(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let connection = connection else { return }
            
            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                while let packet = CompanionPacket.unpack(from: &self.receiveBuffer) {
                    self.processPacket(packet)
                }
            }
            
            if isComplete || error != nil {
                self.handleDisconnection(connection: connection)
                return
            }
            
            self.receiveNextPacket(from: connection)
        }
    }
    
    private func processPacket(_ packet: (type: CompanionMessageType, payload: Data)) {
        switch packet.type {
        case .pencilEvent:
            do {
                let event = try JSONDecoder().decode(PencilDrawEvent.self, from: packet.payload)
                Task { @MainActor in
                    RecDriveOverlayAdapter.shared.handlePencilEvent(event)
                }
            } catch {
                print("[iPadBridgeServer] Failed to decode pencil event: \(error)")
            }
        case .videoFrame:
            break
        }
    }
    
    private func handleDisconnection(connection: NWConnection) {
        guard activeConnection === connection else { return }
        activeConnection = nil
        isClientConnected = false
        receiveBuffer.removeAll()
        print("[iPadBridgeServer] iPad client disconnected")
        
        onClientDisconnected?()
        Task { @MainActor in
            ScreenMirrorStreamer.shared.stopStreaming()
        }
    }
}
