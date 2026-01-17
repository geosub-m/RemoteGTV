import Foundation

/// A lightweight helper to encode data in Protocol Buffer format (wire types).
/// Does not require the official SwiftProtobuf library.
struct ProtocolBuffer {
    
    enum WireType: Int {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case startGroup = 3 // Deprecated
        case endGroup = 4   // Deprecated
        case fixed32 = 5
    }

    /// Encode a key (field number and wire type) into a Varint.
    static func encodeTag(field: Int, wireType: WireType) -> [UInt8] {
        let key = (field << 3) | wireType.rawValue
        return encodeVarint(UInt64(key))
    }

    /// Encode a UInt64 as a Varint.
    static func encodeVarint(_ value: UInt64) -> [UInt8] {
        var buffer = [UInt8]()
        var v = value
        while v >= 0x80 {
            buffer.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        buffer.append(UInt8(v))
        return buffer
    }

    /// Decode a Varint from Data. Returns (value, bytesRead).
    static func decodeVarint(_ data: Data) -> (UInt64, Int) {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var bytesRead = 0
        
        for byte in data {
            bytesRead += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return (value, bytesRead)
            }
            shift += 7
            if shift >= 64 { break }
        }
        return (value, bytesRead)
    }
}
