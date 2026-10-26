import Foundation

/// Incoming command parsed from a single line of JSON received over TCP.
public struct IncomingCommand: Codable {
    public let type: String
    
    // Presentation actions ("next", "prev", "play", "escape", "black_screen", "white_screen")
    public let action: String?
    
    // Direct key presses
    public let code: Int?
    public let modifiers: [String]?
    
    // Named shortcuts
    public let name: String?
    
    // Mouse movement & scrolling
    public let dx: Double?
    public let dy: Double?
    public let button: String?
    
    // Text typing
    public let text: String?
    
    // Ping timestamp
    public let timestamp: Double?
    
    public init(
        type: String,
        action: String? = nil,
        code: Int? = nil,
        modifiers: [String]? = nil,
        name: String? = nil,
        dx: Double? = nil,
        dy: Double? = nil,
        button: String? = nil,
        text: String? = nil,
        timestamp: Double? = nil
    ) {
        self.type = type
        self.action = action
        self.code = code
        self.modifiers = modifiers
        self.name = name
        self.dx = dx
        self.dy = dy
        self.button = button
        self.text = text
        self.timestamp = timestamp
    }
}

/// Outgoing response sent back to the Android client.
public struct OutgoingResponse: Codable {
    public let type: String
    public let message: String?
    public let serverName: String?
    public let timestamp: Double?
    
    public init(type: String, message: String? = nil, serverName: String? = nil, timestamp: Double? = nil) {
        self.type = type
        self.message = message
        self.serverName = serverName
        self.timestamp = timestamp
    }
}
