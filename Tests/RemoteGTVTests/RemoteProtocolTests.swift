import XCTest
@testable import RemoteGTV

final class RemoteProtocolTests: XCTestCase {
    
    func testDeviceInfoSerialization() {
        let info = DeviceInfo(model: "TestModel", vendor: "TestVendor", unknown1: 1, version: "1.0", packageName: "com.pkg", appVersion: "1.0")
        let serializedInfo = info.serialize()
        XCTAssertTrue(serializedInfo.count > 0, "DeviceInfo serialization should not be empty")
        
        let modelBytes = "TestModel".data(using: .utf8)!
        XCTAssertNotNil(serializedInfo.range(of: modelBytes), "DeviceInfo should contain 'TestModel'")
    }
    
    func testRemoteKeyInjectSerialization() {
        let keyInject = RemoteKeyInject(keycode: .dpadCenter, direction: .press)
        let serializedKey = keyInject.serialize()
        // Tag 1 (08) -> Keycode (23 = 0x17)
        // Tag 2 (10) -> Direction (1)
        // Expected: 08 17 10 01
        let expectedKeyBytes: [UInt8] = [0x08, 0x17, 0x10, 0x01]
        XCTAssertEqual(Array(serializedKey), expectedKeyBytes, "RemoteKeyInject serialization")
    }
    
    func testOuterMessageSerialization() {
        let pairingReq = PairingRequest(clientName: "test", serviceName: "test")
        let outer = OuterMessage(pairingRequest: pairingReq)
        let serializedOuter = outer.serialize()
        XCTAssertTrue(serializedOuter.count > 0, "OuterMessage serialization")
        
        let expectedPrefix: [UInt8] = [0x08, 0x02, 0x10, 0xc8, 0x01, 0x52]
        XCTAssertEqual(Array(serializedOuter.prefix(6)), expectedPrefix, "OuterMessage header check")
    }
    
    func testRemoteConfigure() {
        let info2 = DeviceInfo(model: "M", vendor: "V", unknown1: 1, version: "1", packageName: "P", appVersion: "1")
        let config = RemoteConfigure(code1: 123, deviceInfo: info2)
        let serializedConfig = config.serialize()
        XCTAssertTrue(serializedConfig.count > 0, "RemoteConfigure serialization")
    }
    
    func testPingRequest() {
        let ping = PingRequest(val1: 42)
        let serializedPing = ping.serialize()
        XCTAssertEqual(Array(serializedPing), [0x08, 0x2A], "PingRequest serialization")
    }
    
    func testOptionsAndConfiguration() {
        let enc = ProtoEncoding(type: 3, symbolLength: 6)
        let options = Options(inputEncodings: [enc], outputEncodings: [], preferredRole: 1)
        let serializedOptions = options.serialize()
        XCTAssertTrue(serializedOptions.count > 0, "Options serialization")
        
        let configuration = Configuration(encoding: enc, clientRole: 1)
        let serializedConfiguration = configuration.serialize()
        XCTAssertTrue(serializedConfiguration.count > 0, "Configuration serialization")
    }
    
    func testPairingSecret() {
        let secretData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let secret = PairingSecret(secret: secretData)
        let serializedSecret = secret.serialize()
        // Tag 1 (0A) -> Length (4) -> Bytes
        let expectedSecretValues: [UInt8] = [0x0A, 0x04, 0xDE, 0xAD, 0xBE, 0xEF]
        XCTAssertEqual(Array(serializedSecret), expectedSecretValues, "PairingSecret serialization")
    }
}
