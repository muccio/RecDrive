import Foundation
import Network
import UIKit
import Combine

/// Peer-to-peer networking client running on the iPad.
/// Uses Bonjour discovery (NWBrowser) to detect the Mac running RecDrive,
/// establishes an ultra-low latency peer-to-peer TCP connection,
/// receives and decodes JPEG video frames, and transmits Apple Pencil drawing events.
@MainActor
public final class MacConnectionClient: ObservableObject {
    public static let shared = MacConnectionClient()
    
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var connectionStatus: String = "In ricerca Mac..."
    @Published public private(set) var currentFrame: UIImage? = nil
    @Published public private(set) var discoveredEndpointName: String? = nil
    
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let queue = DispatchQueue(label: "com.recdrive.pad.network", qos: .userInteractive)
    
    private var lastDiscoveredEndpoint: NWEndpoint?
    private var lastFrameReceivedTime: Date?
    private var heartbeatTimer: Timer?
    private var reconnectTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isAppActive: Bool = true
    
    private init() {
        startHeartbeatMonitor()
    }
    
    // MARK: - App Lifecycle Handlers
    
    public func handleAppDidEnterBackground() {
        isAppActive = false
        // Request background execution time from iOS to allow socket to stay connected briefly or pause cleanly
        if backgroundTaskID == .invalid {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "com.recdrive.pad.keepalive") { [weak self] in
                self?.endBackgroundTask()
            }
        }
    }
    
    public func handleAppDidBecomeActive() {
        isAppActive = true
        endBackgroundTask()
        
        // When returning to foreground, check connection health immediately
        if !isConnected || connection == nil {
            print("[MacConnectionClient] App active: not connected, restarting discovery...")
            restartBrowsing()
        } else if let lastTime = lastFrameReceivedTime, Date().timeIntervalSince(lastTime) > 3.0 {
            // If connection exists but video stream stalled while in background, trigger reconnect
            print("[MacConnectionClient] App active: video stream stalled (>3s), reconnecting...")
            reconnect()
        } else {
            // Send immediate heartbeat probe to verify socket is alive
            sendHeartbeat()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    // MARK: - Bonjour Discovery & Connection
    
    /// Starts browsing for the RecDrive Bonjour service on the local network or peer-to-peer Wi-Fi/AWDL.
    public func startBrowsing() {
        guard browser == nil else { return }
        
        connectionStatus = "In ricerca Mac..."
        
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_recdrive-pad._tcp", domain: nil)
        let newBrowser = NWBrowser(for: descriptor, using: parameters)
        
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let firstResult = results.first {
                    self.lastDiscoveredEndpoint = firstResult.endpoint
                    if !self.isConnected && self.connection == nil {
                        self.connect(to: firstResult.endpoint)
                    }
                }
            }
        }
        
        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.connectionStatus = self.isConnected ? "Connesso al Mac" : "Ricerca RecDrive Mac attiva..."
                case .failed(let error):
                    let errorDesc = error.localizedDescription
                    if errorDesc.contains("-65555") || errorDesc.contains("NoAuth") {
                        self.connectionStatus = "Permesso Rete Locale richiesto: abilita 'Rete Locale' nelle Impostazioni iPad > RecDrive Pad."
                    } else {
                        self.connectionStatus = "Errore ricerca: \(errorDesc)"
                    }
                case .cancelled:
                    if !self.isConnected {
                        self.connectionStatus = "Ricerca interrotta"
                    }
                default:
                    break
                }
            }
        }
        
        newBrowser.start(queue: queue)
        self.browser = newBrowser
    }
    
    /// Restarts Bonjour discovery from scratch.
    public func restartBrowsing() {
        disconnect()
        browser?.cancel()
        browser = nil
        startBrowsing()
    }
    
    /// Connects directly to a specific IP address and port (useful if Bonjour multicast is blocked by Wi-Fi).
    public func connectToHost(_ hostString: String, port: UInt16 = 19842) {
        let cleanHost = hostString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty, let targetPort = NWEndpoint.Port(rawValue: port) else { return }
        
        disconnect()
        browser?.cancel()
        browser = nil
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(cleanHost), port: targetPort)
        self.lastDiscoveredEndpoint = endpoint
        connect(to: endpoint)
    }
    
    /// Connects to a specific discovered endpoint.
    public func connect(to endpoint: NWEndpoint) {
        // Avoid duplicate concurrent connection attempts
        guard connection == nil else { return }
        
        self.lastDiscoveredEndpoint = endpoint
        connectionStatus = "Connessione in corso..."
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        tcpOptions.keepaliveInterval = 2
        tcpOptions.keepaliveCount = 3
        tcpOptions.noDelay = true
        
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.includePeerToPeer = true
        parameters.serviceClass = .interactiveVideo
        
        let newConnection = NWConnection(to: endpoint, using: parameters)
        
        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let self = self, let conn = newConnection else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.isConnected = true
                    self.discoveredEndpointName = endpoint.debugDescription
                    self.connectionStatus = "Connesso al Mac"
                    self.lastFrameReceivedTime = Date()
                    self.receiveBuffer.removeAll()
                    self.receiveNextChunk(from: conn)
                    self.sendHeartbeat()
                case .failed(let error):
                    self.handleDisconnection(error: error.localizedDescription)
                case .cancelled:
                    self.handleDisconnection(error: nil)
                case .waiting(let error):
                    self.connectionStatus = "In attesa connessione: \(error.localizedDescription)"
                default:
                    break
                }
            }
        }
        
        newConnection.start(queue: queue)
        self.connection = newConnection
    }
    
    /// Reconnects to the last known endpoint or restarts discovery.
    public func reconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        receiveBuffer.removeAll()
        
        if let endpoint = lastDiscoveredEndpoint {
            connect(to: endpoint)
        } else {
            restartBrowsing()
        }
    }
    
    /// Disconnects from current Mac and resumes browsing.
    public func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        isConnected = false
        connectionStatus = "Disconnesso"
    }
    
    // MARK: - Streaming Reception
    
    private func receiveNextChunk(from conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak conn] data, _, isComplete, error in
            guard let self = self, let activeConn = conn else { return }
            
            if let data = data, !data.isEmpty {
                self.queue.async {
                    self.receiveBuffer.append(data)
                    
                    while let packet = CompanionPacket.unpack(from: &self.receiveBuffer) {
                        self.processIncomingPacket(packet)
                    }
                }
            }
            
            if isComplete || error != nil {
                Task { @MainActor in
                    self.handleDisconnection(error: error?.localizedDescription)
                }
                return
            }
            
            self.receiveNextChunk(from: activeConn)
        }
    }
    
    private nonisolated func processIncomingPacket(_ packet: (type: CompanionMessageType, payload: Data)) {
        switch packet.type {
        case .videoFrame:
            if let image = UIImage(data: packet.payload) {
                Task { @MainActor in
                    self.lastFrameReceivedTime = Date()
                    self.currentFrame = image
                    if !self.isConnected {
                        self.isConnected = true
                        self.connectionStatus = "Connesso al Mac"
                    }
                }
            }
        case .heartbeat:
            Task { @MainActor in
                self.lastFrameReceivedTime = Date()
            }
        case .pencilEvent:
            break
        }
    }
    
    private func handleDisconnection(error: String?) {
        connection = nil
        isConnected = false
        receiveBuffer.removeAll()
        
        if let error = error {
            connectionStatus = "Disconnesso: \(error)"
        } else {
            connectionStatus = "Riconnessione al Mac..."
        }
        
        // Auto-reconnect if app is in foreground
        scheduleAutoReconnect()
    }
    
    private func scheduleAutoReconnect() {
        guard isAppActive else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, !self.isConnected, self.connection == nil else { return }
            print("[MacConnectionClient] Auto-reconnecting...")
            self.reconnect()
        }
    }
    
    // MARK: - Heartbeat & Keepalive Monitor
    
    private func startHeartbeatMonitor() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.isConnected && self.connection != nil else { return }
                
                // If connected but no video frame or heartbeat received for > 5 seconds, stream is dead
                if let lastFrame = self.lastFrameReceivedTime, Date().timeIntervalSince(lastFrame) > 5.0 {
                    print("[MacConnectionClient] Watchdog: Stream dead (>5s without frames). Triggering reconnect.")
                    self.reconnect()
                    return
                }
                
                self.sendHeartbeat()
            }
        }
    }
    
    private func sendHeartbeat() {
        guard isConnected, let connection = connection else { return }
        queue.async {
            let packet = CompanionPacket.pack(type: .heartbeat, payload: Data())
            connection.send(content: packet, completion: .idempotent)
        }
    }
    
    // MARK: - Transmit Pencil Events
    
    /// Transmits a PencilDrawEvent to the connected Mac.
    public func sendPencilEvent(_ event: PencilDrawEvent) {
        guard isConnected, let connection = connection else { return }
        
        queue.async {
            do {
                let jsonData = try JSONEncoder().encode(event)
                let packet = CompanionPacket.pack(type: .pencilEvent, payload: jsonData)
                connection.send(content: packet, completion: .idempotent)
            } catch {
                print("[MacConnectionClient] Failed to encode PencilDrawEvent: \(error)")
            }
        }
    }
}
