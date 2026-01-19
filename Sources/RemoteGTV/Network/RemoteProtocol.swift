import Foundation

enum Keycode: Int, Codable {
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case dpadUp = 19
    case dpadCenter = 23
    case back = 4
    case home = 3
    case volumeUp = 24
    case volumeDown = 25
    case mute = 164
    case playPause = 85
    case power = 26
}

enum Direction: Int, Codable {
    case press = 1      // Key pressed (down)
    case release = 2    // Key released (up)
    case short = 3      // Short press (single click)
}

struct DeviceInfo {
    let model: String
    let vendor: String
    let unknown1: Int
    let version: String
    let packageName: String
    let appVersion: String
    
    func serialize() -> Data {
        var data = Data()
        data.append(0x0a) // Tag 1: model
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(model.count)))
        data.append(contentsOf: model.utf8)
        
        data.append(0x12) // Tag 2: vendor
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(vendor.count)))
        data.append(contentsOf: vendor.utf8)
        
        data.append(0x18) // Tag 3: unknown1
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(unknown1)))
        
        data.append(0x22) // Tag 4: version (e.g. Android version)
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(version.count)))
        data.append(contentsOf: version.utf8)
        
        data.append(0x2a) // Tag 5: packageName
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(packageName.count)))
        data.append(contentsOf: packageName.utf8)
        
        data.append(0x32) // Tag 6: appVersion (e.g. Remote app version)
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(appVersion.count)))
        data.append(contentsOf: appVersion.utf8)
        
        return data
    }
}

struct RemoteConfigure {
    let code1: Int
    let deviceInfo: DeviceInfo
    
    func serialize() -> Data {
        var data = Data()
        data.append(0x08) // Tag 1: code1 (Varint)
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(code1)))
        
        data.append(0x12) // Tag 2: deviceInfo (Message)
        let d = deviceInfo.serialize()
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
        data.append(d)
        
        return data
    }
}

struct RemoteKeyInject {
    let keycode: Keycode
    let direction: Direction
    
    func serialize() -> Data {
        var data = Data()
        // Try just keycode, no direction (simpler format)
        data.append(0x08) // Tag 1: keycode
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(keycode.rawValue)))
        
        // Include direction
        data.append(0x10) // Tag 2: direction
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(direction.rawValue)))
        
        return data
    }
}

struct PingRequest {
    let val1: Int32
    
    func serialize() -> Data {
        var data = Data()
        data.append(0x08) // Tag 1
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(val1)))
        return data
    }
}

struct PingResponse {
    let val1: Int32
    
    func serialize() -> Data {
        var data = Data()
        data.append(0x08) // Tag 1
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(val1)))
        return data
    }
}

struct RemoteVoiceBegin {
    let requestId: UInt32
    
    func serialize() -> Data {
        var data = Data()
        data.append(0x08) // Tag 1 (Varint)
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(requestId)))
        return data
    }
}

struct RemoteVoicePayload {
    let data: Data
    
    func serialize() -> Data {
        var d = Data()
        d.append(0x0a) // Tag 1 (Bytes)
        d.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(data.count)))
        d.append(data)
        return d
    }
}

struct RemoteVoiceEnd {
    // Empty message usually, or contains requestId
    func serialize() -> Data {
        return Data()
    }
}

struct RemoteMessage {
    var remoteConfigure: RemoteConfigure? = nil
    var remoteConfigureAck: RemoteConfigure? = nil
    var remoteKeyInject: RemoteKeyInject? = nil
    var pingRequest: PingRequest? = nil
    var pingResponse: PingResponse? = nil
    var voiceBegin: RemoteVoiceBegin? = nil   // Tag 11
    var voicePayload: RemoteVoicePayload? = nil // Tag 12
    var voiceEnd: RemoteVoiceEnd? = nil       // Tag 13
    
    func serialize() -> Data {
        var innerData = Data()
        if let config = remoteConfigure {
            innerData.append(0x0a) // Tag 1 (1 << 3 | 2)
            let d = config.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        } else if let ack = remoteConfigureAck {
            innerData.append(0x12) // Tag 2
            let d = ack.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        } else if let key = remoteKeyInject {
            innerData.append(0x52) // Tag 10
            let d = key.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        } else if let ping = pingRequest {
            innerData.append(0x42) // Tag 8
            let d = ping.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        } else if let resp = pingResponse {
            innerData.append(0x4a) // Tag 9
            let d = resp.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        } else if let begin = voiceBegin {
            innerData.append(0x5a) // Tag 11 (11 << 3 | 2 = 88 + 2 = 90 = 0x5a)
            let d = begin.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        } else if let payload = voicePayload {
            innerData.append(0x62) // Tag 12 (12 << 3 | 2 = 96 + 2 = 98 = 0x62)
            let d = payload.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        } else if let end = voiceEnd {
            innerData.append(0x6a) // Tag 13 (13 << 3 | 2 = 104 + 2 = 106 = 0x6a)
            let d = end.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        }
        return innerData
    }
}

// Pairing Messages (OuterMessage)
struct PairingRequest {
    let clientName: String
    let serviceName: String
    var deviceInfo: DeviceInfo? = nil
    
    func serialize() -> Data {
        var data = Data()
        data.append(0x0a) // Tag 1: clientName
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(clientName.count)))
        data.append(contentsOf: clientName.utf8)
        
        data.append(0x12) // Tag 2: serviceName
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(serviceName.count)))
        data.append(contentsOf: serviceName.utf8)
        
        if let info = deviceInfo {
            data.append(0x1a) // Tag 3: deviceInfo (Message)
            let d = info.serialize()
            data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            data.append(d)
        }
        
        return data
    }
}

struct Options {
    let inputEncodings: [ProtoEncoding]
    let outputEncodings: [ProtoEncoding]
    let preferredRole: Int
    
    func serialize() -> Data {
        var data = Data()
        for enc in inputEncodings {
            data.append(0x0a) // Tag 1: inputEncoding (Message)
            let d = enc.serialize()
            data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            data.append(d)
        }
        for enc in outputEncodings {
            data.append(0x12) // Tag 2: outputEncoding (Message)
            let d = enc.serialize()
            data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            data.append(d)
        }
        data.append(0x18) // Tag 3: preferredRole
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(preferredRole)))
        return data
    }
}

struct ProtoEncoding {
    let type: Int
    let symbolLength: Int
    
    func serialize() -> Data {
        var data = Data()
        data.append(0x08) // Tag 1: type
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(type)))
        data.append(0x10) // Tag 2: symbolLength
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(symbolLength)))
        return data
    }
}

struct Configuration {
    let encoding: ProtoEncoding
    let clientRole: Int
    
    func serialize() -> Data {
        var data = Data()
        data.append(0x0a) // Tag 1: encoding (Message)
        let d = encoding.serialize()
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
        data.append(d)
        
        data.append(0x10) // Tag 2: clientRole
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(clientRole)))
        return data
    }
}

struct PairingSecret {
    let secret: Data
    
    func serialize() -> Data {
        var data = Data()
        data.append(0x0a) // Tag 1: secret (bytes)
        data.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(secret.count)))
        data.append(secret)
        return data
    }
}

struct OuterMessage {
    var protocolVersion: Int = 2
    var status: Int = 200
    var pairingRequest: PairingRequest? = nil
    var options: Options? = nil
    var configuration: Configuration? = nil
    var secret: PairingSecret? = nil
    
    func serialize() -> Data {
        var innerData = Data()
        
        innerData.append(0x08) // Tag 1: protocolVersion
        innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(protocolVersion)))
        
        innerData.append(0x10) // Tag 2: status
        innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(status)))
        
        if let req = pairingRequest {
            innerData.append(0x52) // Tag 10: pairingRequest
            let d = req.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        } else if let opt = options {
            innerData.append(0xa2) // Field 20: Tag 162
            innerData.append(0x01) // continuation
            let d = opt.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        } else if let config = configuration {
            innerData.append(0xf2) // Field 30: Tag 242
            innerData.append(0x01) // continuation
            let d = config.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        } else if let sec = secret {
            innerData.append(0xc2) // Field 40: Tag 322
            innerData.append(0x02) // continuation
            let d = sec.serialize()
            innerData.append(contentsOf: ProtocolBuffer.encodeVarint(UInt64(d.count)))
            innerData.append(d)
        }
        
        return innerData
    }
}
