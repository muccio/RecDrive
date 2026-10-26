import Foundation
import Network

/// TCP server receiving remote control commands from the Android companion app.
/// Advertises service via Bonjour (_recdrive-remote._tcp) and accepts direct IP connections.
public final class RemoteServer: @unchecked Sendable {
    public static let shared = RemoteServer()
    public static let serviceType = "_recdrive-remote._tcp"
    public static let defaultPort: UInt16 = 19850
    
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.recdrive.android.remote.server", qos: .userInteractive)
    private let connectionLock = NSLock()
    
    public var onClientCountChanged: (@Sendable (Int) -> Void)?
    public var onStatusChanged: (@Sendable (String) -> Void)?
    
    private(set) public var isRunning = false
    private(set) public var currentPort: UInt16 = defaultPort
    
    private init() {}
    
    // MARK: - Server Lifecycle
    
    public func start(port: UInt16 = defaultPort) {
        guard !isRunning else { return }
        self.currentPort = port
        
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.noDelay = true
            
            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            parameters.includePeerToPeer = true
            parameters.allowLocalEndpointReuse = true
            
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                print("[RemoteServer] Invalid port: \(port)")
                return
            }
            
            let newListener = try NWListener(using: parameters, on: endpointPort)
            newListener.service = NWListener.Service(type: Self.serviceType)
            
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    let portVal = newListener.port?.rawValue ?? port
                    self.currentPort = portVal
                    let msg = "Pronto su porta \(portVal) (Bonjour: \(Self.serviceType))"
                    print("[RemoteServer] \(msg)")
                    self.onStatusChanged?(msg)
                case .failed(let error):
                    let msg = "Errore server: \(error.localizedDescription)"
                    print("[RemoteServer] \(msg)")
                    self.onStatusChanged?(msg)
                    self.stop()
                case .cancelled:
                    self.onStatusChanged?("Disattivato")
                default:
                    break
                }
            }
            
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            newListener.start(queue: queue)
            self.listener = newListener
            self.isRunning = true
            print("[RemoteServer] Avviato listener su porta \(port)")
        } catch {
            print("[RemoteServer] Impossibile avviare listener: \(error)")
        }
    }
    
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        
        connectionLock.lock()
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        connectionLock.unlock()
        
        listener?.cancel()
        listener = nil
        onClientCountChanged?(0)
        onStatusChanged?("Disattivato")
        print("[RemoteServer] Server arrestato")
    }
    
    // MARK: - Connection Handling
    
    private func handleNewConnection(_ connection: NWConnection) {
        connectionLock.lock()
        activeConnections.append(connection)
        let count = activeConnections.count
        connectionLock.unlock()
        
        onClientCountChanged?(count)
        print("[RemoteServer] Nuovo client Android connesso da: \(connection.endpoint)")
        
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .ready:
                self.receiveNextLine(from: connection, buffer: Data())
            case .failed(let error):
                print("[RemoteServer] Connessione client fallita: \(error)")
                self.removeConnection(connection)
            case .cancelled:
                self.removeConnection(connection)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connectionLock.lock()
        activeConnections.removeAll { $0 === connection }
        let count = activeConnections.count
        connectionLock.unlock()
        
        onClientCountChanged?(count)
        print("[RemoteServer] Client disconnesso. Connessioni attive: \(count)")
    }
    
    // MARK: - Line-delimited Message Receiving
    
    private func receiveNextLine(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let connection = connection else { return }
            
            if let error = error {
                print("[RemoteServer] Errore ricezione: \(error)")
                self.removeConnection(connection)
                return
            }
            
            var currentBuffer = buffer
            if let data = data, !data.isEmpty {
                currentBuffer.append(data)
                
                // Process lines separated by newline \n
                while let newlineIndex = currentBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = currentBuffer.subdata(in: 0..<newlineIndex)
                    currentBuffer.removeSubrange(0...newlineIndex)
                    
                    if !lineData.isEmpty {
                        self.processLine(lineData, from: connection)
                    }
                }
            }
            
            if isComplete {
                self.removeConnection(connection)
                return
            }
            
            self.receiveNextLine(from: connection, buffer: currentBuffer)
        }
    }
    
    private func processLine(_ data: Data, from connection: NWConnection) {
        do {
            let command = try JSONDecoder().decode(IncomingCommand.self, from: data)
            
            // Handle ping immediately with pong
            if command.type == "ping" {
                let response = OutgoingResponse(
                    type: "pong",
                    message: "RecDrive Remote Server Ready",
                    serverName: Host.current().localizedName ?? "Mac",
                    timestamp: Date().timeIntervalSince1970
                )
                sendResponse(response, to: connection)
                return
            }
            
            // Dispatch input command
            InputSynthesizer.shared.execute(command)
        } catch {
            if let str = String(data: data, encoding: .utf8) {
                print("[RemoteServer] Impossibile decodificare comando JSON: '\(str)' - errore: \(error)")
            }
        }
    }
    
    private func sendResponse(_ response: OutgoingResponse, to connection: NWConnection) {
        do {
            var data = try JSONEncoder().encode(response)
            data.append(UInt8(ascii: "\n"))
            connection.send(content: data, completion: .idempotent)
        } catch {
            print("[RemoteServer] Errore invio risposta: \(error)")
        }
    }
    
    // MARK: - IP Address Discovery
    
    /// Returns the primary local IPv4 address (e.g. 192.168.1.x) of this Mac for manual pairing.
    public static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            
            // Filter: must be active (IFF_UP), running (IFF_RUNNING), not loopback (IFF_LOOPBACK)
            if (flags & (IFF_UP | IFF_RUNNING)) != 0 && (flags & IFF_LOOPBACK) == 0 {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        ptr.pointee.ifa_addr,
                        socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        let ifName = String(cString: ptr.pointee.ifa_name)
                        // Prefer en0 (Wi-Fi) or en1/en2
                        if ifName == "en0" {
                            return String(cString: hostname)
                        } else if address == nil {
                            address = String(cString: hostname)
                        }
                    }
                }
            }
        }
        return address
    }
}
