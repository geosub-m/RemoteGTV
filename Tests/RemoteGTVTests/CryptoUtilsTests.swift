import XCTest
@testable import RemoteGTV

final class CryptoUtilsTests: XCTestCase {
    
    func testSHA256Digest() {
        // SHA256("test") = 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
        let testData = "test".data(using: .utf8)!
        let (digest, hex) = CryptoUtils.getDigest(data: [testData])
        
        XCTAssertEqual(digest.count, 32, "SHA256 digest length should be 32 bytes")
        XCTAssertEqual(hex, "9F", "Hex prefix should be 9F")
    }
    
    func testMultiPartDigest() {
        let p1 = "part1".data(using: .utf8)!
        let p2 = "part2".data(using: .utf8)!
        
        let combined = "part1part2".data(using: .utf8)!
        let (digestCombined, _) = CryptoUtils.getDigest(data: [combined])
        let (digestSplit, _) = CryptoUtils.getDigest(data: [p1, p2])
        
        XCTAssertEqual(Array(digestCombined), Array(digestSplit), "Multi-part digest should match combined digest")
    }
}
