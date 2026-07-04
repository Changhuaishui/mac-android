import Foundation

/// protocol v0 消息类型
enum MessageType: UInt16 {
    case hello        = 0
    case videoConfig  = 1
    case videoFrame   = 2
    case ping         = 3
    case error        = 4
}


/// protocol v0 flags
struct ProtocolFlags {
    static let keyframe: UInt32 = 0x00000001
    static let config: UInt32   = 0x00000002
    static let endOfStream: UInt32 = 0x00000004
}

/// protocol v0 帧头，固定 32 字节
struct ProtocolHeader {
    static let size: Int = 32
    static let magic: UInt32 = 0x4D414453 // "MADS"
    static let version: UInt16 = 0

    let type: MessageType
    let sequence: UInt64
    let timestampNs: UInt64
    let flags: UInt32
    let payloadLength: UInt32

    func encode() -> Data {
        var data = Data()
        data.reserveCapacity(ProtocolHeader.size)
        data.appendUInt32(ProtocolHeader.magic)
        data.appendUInt16(ProtocolHeader.version)
        data.appendUInt16(type.rawValue)
        data.appendUInt64(sequence)
        data.appendUInt64(timestampNs)
        data.appendUInt32(flags)
        data.appendUInt32(payloadLength)
        return data
    }

    init(type: MessageType, sequence: UInt64, timestampNs: UInt64, flags: UInt32, payloadLength: UInt32) {
        self.type = type
        self.sequence = sequence
        self.timestampNs = timestampNs
        self.flags = flags
        self.payloadLength = payloadLength
    }

    /// 从 32 字节大端数据解析帧头
    init?(data: Data) {
        guard data.count == ProtocolHeader.size else { return nil }
        let magic = data.readUInt32(at: 0)
        guard magic == ProtocolHeader.magic else { return nil }
        let version = data.readUInt16(at: 4)
        guard version == ProtocolHeader.version else { return nil }
        let typeValue = data.readUInt16(at: 6)
        guard let type = MessageType(rawValue: typeValue) else { return nil }
        self.type = type
        self.sequence = data.readUInt64(at: 8)
        self.timestampNs = data.readUInt64(at: 16)
        self.flags = data.readUInt32(at: 24)
        self.payloadLength = data.readUInt32(at: 28)
    }
}

extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16(_ value: UInt16) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }

    mutating func appendUInt64(_ value: UInt64) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }

    func readUInt8(at offset: Int) -> UInt8 {
        return self[offset]
    }

    func readUInt16(at offset: Int) -> UInt16 {
        return (UInt16(self[offset]) << 8) |
               UInt16(self[offset + 1])
    }

    func readUInt32(at offset: Int) -> UInt32 {
        return (UInt32(self[offset]) << 24) |
               (UInt32(self[offset + 1]) << 16) |
               (UInt32(self[offset + 2]) << 8) |
               UInt32(self[offset + 3])
    }

    func readUInt64(at offset: Int) -> UInt64 {
        return (UInt64(self[offset]) << 56) |
               (UInt64(self[offset + 1]) << 48) |
               (UInt64(self[offset + 2]) << 40) |
               (UInt64(self[offset + 3]) << 32) |
               (UInt64(self[offset + 4]) << 24) |
               (UInt64(self[offset + 5]) << 16) |
               (UInt64(self[offset + 6]) << 8) |
               UInt64(self[offset + 7])
    }
}
