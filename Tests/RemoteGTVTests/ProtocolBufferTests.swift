import XCTest
@testable import RemoteGTV

final class ProtocolBufferTests: XCTestCase {
    
    func testVarintEncoding() {
        // Test 1: Varint Encoding
        let value1: UInt64 = 150
        let encoded1 = ProtocolBuffer.encodeVarint(value1)
        // 150 = 0x96 01 in varint
        let expected1: [UInt8] = [0x96, 0x01]
        XCTAssertEqual(encoded1, expected1, "Varint encoding of 150")
    }
    
    func testVarintDecoding() {
        // Test 2: Varint Decoding
        let data = Data([0x96, 0x01])
        let (decoded1, bytesRead1) = ProtocolBuffer.decodeVarint(data)
        XCTAssertEqual(decoded1, 150, "Varint decoding of 150")
        XCTAssertEqual(bytesRead1, 2, "Varint decoding bytes read")
    }
    
    func testTagEncoding() {
        // Test 3: Tag Encoding
        // Field 1, WireType.varint (0) -> (1 << 3) | 0 = 8 -> 0x08
        let tag = ProtocolBuffer.encodeTag(field: 1, wireType: .varint)
        XCTAssertEqual(tag, [0x08], "Tag encoding for Field 1, Varint")
    }
}
