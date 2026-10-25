import Foundation
import CoreGraphics

/// Types of framed messages exchanged over the peer-to-peer TCP connection.
public enum CompanionMessageType: UInt8 {
    case videoFrame = 0x01
    case pencilEvent = 0x02
    case heartbeat = 0x03
}

/// Lifecycle phases for drawing actions originating from iPad / Apple Pencil.
public enum PencilPhase: String, Codable {
    case began
    case moved
    case ended
    case cancelled
    case clearAll
    case undo
}

/// Normalized drawing event sent from the iPad to the Mac overlay.
public struct PencilDrawEvent: Codable {
    public let phase: PencilPhase
    public let normalizedX: Double   // 0.0 ... 1.0 (da sinistra a destra)
    public let normalizedY: Double   // 0.0 ... 1.0 (dall'alto in basso)
    public let force: Double         // 0.0 ... 1.0
    public let lineWidth: Double
    public let colorHex: String      // es. "#FF3B30"
    public let isEraser: Bool
    
    public init(
        phase: PencilPhase,
        normalizedX: Double = 0.0,
        normalizedY: Double = 0.0,
        force: Double = 1.0,
        lineWidth: Double = 6.0,
        colorHex: String = "#FF3B30",
        isEraser: Bool = false
    ) {
        self.phase = phase
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.force = force
        self.lineWidth = lineWidth
        self.colorHex = colorHex
        self.isEraser = isEraser
    }
}

/// Protocol framing helper to pack and unpack 5-byte fixed-header messages over a continuous TCP stream.
/// Header format: [Byte 0: UInt8 MessageType][Bytes 1..4: UInt32 Big-Endian PayloadLength]
public enum CompanionPacket {
    public static let headerSize = 5
    
    /// Packs a message type and raw payload into a 5-byte framed Data buffer.
    public static func pack(type: CompanionMessageType, payload: Data) -> Data {
        var data = Data(capacity: headerSize + payload.count)
        var typeByte = type.rawValue
        var payloadLength = UInt32(payload.count).bigEndian
        
        data.append(&typeByte, count: 1)
        withUnsafeBytes(of: &payloadLength) { rawBuffer in
            data.append(contentsOf: rawBuffer)
        }
        data.append(payload)
        return data
    }
    
    /// Attempts to unpack one complete message from the streaming buffer.
    /// If successful, returns the parsed message and removes the consumed bytes from the buffer.
    /// Returns nil if fewer than 5 bytes are available or if the full payload hasn't arrived yet.
    public static func unpack(from buffer: inout Data) -> (type: CompanionMessageType, payload: Data)? {
        guard buffer.count >= headerSize else { return nil }
        
        let rawType = buffer[0]
        guard let messageType = CompanionMessageType(rawValue: rawType) else {
            // Unrecognized byte; drop one byte to allow stream resynchronization
            buffer.removeFirst()
            return nil
        }
        
        let payloadLength: UInt32 = buffer.withUnsafeBytes { rawBytes in
            let ptr = rawBytes.baseAddress!.advanced(by: 1).assumingMemoryBound(to: UInt32.self)
            return UInt32(bigEndian: ptr.pointee)
        }
        
        let totalSize = headerSize + Int(payloadLength)
        guard buffer.count >= totalSize else {
            // Full message payload is still incoming over TCP
            return nil
        }
        
        let payload = buffer.subdata(in: headerSize..<totalSize)
        buffer.removeSubrange(0..<totalSize)
        return (type: messageType, payload: payload)
    }
}
