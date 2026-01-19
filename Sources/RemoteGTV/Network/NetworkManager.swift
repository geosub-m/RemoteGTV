import Foundation
import Network
import Security
import Combine
import CryptoKit
import AppKit

class NetworkManager: NSObject, ObservableObject {
    static let shared = NetworkManager()
    
    // Published states for UI
    @Published var connectionState: ConnectionState = .disconnected
    @Published var statusMessage: String = "Initializing..."
    @Published var isPairing: Bool = false
    @Published var discoveredDevices: [NWBrowser.Result] = []
    
    // Delegates to specialized managers
    private let discoveryManager = DiscoveryManager()
    private var cancellables = Set<AnyCancellable>()
    
    // Connection State
    private var connection: NWConnection?
    private var identity: SecIdentity?
    private var serverCertificateData: Data?
    private var currentPort: Int = 0
    private var lastConnectedIP: String?
    private var pingTimer: Timer?
    private var receiveBuffer = Data()
    private var triedControlPortFirst: Bool = false
    private var isConfigured: Bool = false // Remote Config State
    private var netService: NetService? // Keep reference during resolution
    
    // Sleep/Wake
    private var isWakingUp: Bool = false
    private let lastDeviceIPKey = "lastConnectedDeviceIP"
    
    enum ConnectionState: Equatable {
        case disconnected
        case searching
        case connecting
        case connected
        case error(String)
    }
    
    override init() {
        super.init()
        Logger.shared.log("Initializing NetworkManager...", category: "Network")
        
        setupSystemObservers()
        setupDiscovery()
        loadIdentity()
        
        if let savedIP = UserDefaults.standard.string(forKey: lastDeviceIPKey) {
            autoConnect(to: savedIP)
        } else {
            startDiscovery()
        }
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    private func setupDiscovery() {
        discoveryManager.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .assign(to: \.discoveredDevices, on: self)
            .store(in: &cancellables)
    }
    
    private func setupSystemObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onWake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    
    private func loadIdentity() {
        if let cert = CertUtils.shared.loadIdentityFromP12() {
            self.identity = cert
            Logger.shared.log("Certificate loaded successfully.", category: "Network")
        } else {
            Logger.shared.log("No certificate found. Will need to generate or pair.", category: "Network", type: .error)
        }
    }
    
    private func autoConnect(to ip: String) {
        Logger.shared.log("Found saved device IP: \(ip). Auto-connecting...", category: "Network")
        self.lastConnectedIP = ip
        self.triedControlPortFirst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.connectToIP(host: ip, port: 6466)
        }
    }
    
    // MARK: - Discovery & Connection
    
    func startDiscovery() {
        self.connectionState = .searching
        self.statusMessage = "Searching for Android TVs..."
        discoveryManager.startDiscovery()
    }
    
    func connect(to endpoint: NWEndpoint) {
        self.connectionState = .connecting
        Logger.shared.log("Initiating connection process for: \(endpoint)", category: "Connection")
        
        if case .service(let name, let type, let domain, _) = endpoint {
            let service = NetService(domain: domain, type: type, name: name)
            service.delegate = self
            service.resolve(withTimeout: 5.0)
            self.statusMessage = "Resolving \(name)..."
            Logger.shared.log("Resolving Service: \(name) \(type) \(domain)", category: "Connection")
            self.netService = service
        }
    }
    
    func connectToIP(host: String, port: Int) {
         let hostEndpoint = NWEndpoint.Host(host)
         let portEndpoint = NWEndpoint.Port(integerLiteral: UInt16(port))
         
         self.connectionState = .connecting
         self.statusMessage = "Connecting to \(host)..."
         self.currentPort = port
         let parameters = createTLSParameters()
         
         self.connection = NWConnection(host: hostEndpoint, port: portEndpoint, using: parameters)
         self.connection?.stateUpdateHandler = { [weak self] state in
             self?.handleStateUpdate(state)
         }
         
         self.receiveNextMessage()
         self.connection?.start(queue: .main)
    }
    
    private func createTLSParameters() -> NWParameters {
        let options = NWProtocolTLS.Options()
        
        if let identity = self.identity {
            sec_protocol_options_set_local_identity(options.securityProtocolOptions, sec_identity_create(identity)!)
        }
        
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { (sec_protocol_metadata, sec_trust, sec_protocol_verify_complete) in
            let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first {
                self.serverCertificateData = SecCertificateCopyData(certificate) as Data
            }
            sec_protocol_verify_complete(true)
        }, .global())
        
        let parameters = NWParameters(tls: options)
        parameters.includePeerToPeer = false
        return parameters
    }
    
    // MARK: - State Handling
    
    private func handleStateUpdate(_ state: NWConnection.State) {
        Logger.shared.log("Connection state changed: \(state)", category: "Connection")
        switch state {
        case .ready:
            handleReadyState()
        case .failed(let error):
            handleConnectionFailure(error)
        case .cancelled:
            self.connectionState = .disconnected
            self.stopPingTimer()
        default:
            break
        }
    }
    
    private func handleReadyState() {
        Logger.shared.log("Connection READY on port \(self.currentPort).", category: "Connection")
        self.connectionState = .connected
        
        if self.currentPort == 6467 {
            self.statusMessage = "Connected (Sending Pairing Request)"
            self.sendPairingRequest()
        } else {
            self.isConfigured = false
            self.statusMessage = "Remote Connected!"
            self.sendRemoteConfig()
            self.startPingTimer()
        }
    }
    
    private func handleConnectionFailure(_ error: NWError) {
        Logger.shared.log("Connection FAILED: \(error)", category: "Connection", type: .error)
        
        if self.currentPort == 6466 {
            // Auto-retry control port logic
            retryControlPort()
        } else {
            self.connectionState = .error(error.localizedDescription)
            self.statusMessage = "Connection failed: \(error.localizedDescription)"
            self.stopPingTimer()
        }
    }
    
    private func retryControlPort() {
        Logger.shared.log("Retrying 6466 in 2.0s...", category: "Connection")
        self.statusMessage = "Connection lost. Retrying..."
        self.connection?.cancel()
        self.connection = nil
        self.stopPingTimer()
        
        if let ip = self.lastConnectedIP {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                if self.connectionState != .connected && self.connectionState != .connecting {
                    self.connectToIP(host: ip, port: 6466)
                }
            }
        }
    }
    
    // MARK: - Protocol & Data Handling
    
    private func receiveNextMessage() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                self.handleReceiveError(error)
                return
            }
            
            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            } else if isComplete {
                if self.currentPort == 6466 {
                    Logger.shared.log("Connection closed by peer (EOF). Retrying...", category: "Connection")
                    self.retryControlPort()
                } else {
                    self.connectionState = .disconnected
                }
                return
            }
            
            if !isComplete {
                self.receiveNextMessage()
            }
        }
    }
    
    private func handleReceiveError(_ error: NWError) {
        if case .posix(let code) = error, code == .ECANCELED { return }
         Logger.shared.log("Receive error: \(error)", category: "Protocol", type: .error)
         
         if case .posix(let code) = error {
             if code == .ECONNRESET || code == .ENOTCONN || code == .ETIMEDOUT {
                 self.connectionState = .error("Connection lost: \(code)")
                 return
             }
         }
         
         DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
             self.receiveNextMessage()
         }
    }
    
    private func processBuffer() {
        while !receiveBuffer.isEmpty {
            let (length64, bytesRead) = ProtocolBuffer.decodeVarint(receiveBuffer)
            let length = Int(length64)
            
            if bytesRead == 0 || receiveBuffer.count < bytesRead + length { return }
            
            let bodyStart = receiveBuffer.index(receiveBuffer.startIndex, offsetBy: bytesRead)
            let bodyEnd = receiveBuffer.index(bodyStart, offsetBy: length)
            let bodyData = receiveBuffer.subdata(in: bodyStart..<bodyEnd)
            
            receiveBuffer.removeSubrange(receiveBuffer.startIndex..<bodyEnd)
            self.handlePacket(bodyData)
        }
    }
    
    private func handlePacket(_ data: Data) {
        if self.currentPort == 6467 {
            handlePairingPacket(data)
        } else if self.currentPort == 6466 {
            handleControlPacket(data)
        }
    }
    
    // MARK: - Packet Type Handlers (Extracted)
    
    private func handlePairingPacket(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        
        if hex.contains("ca02") { // SecretAck (Tag 41)
            Logger.shared.log("Secret Acknowledged! Pairing SUCCESS.", category: "Pairing")
            self.isPairing = false
            self.connectionState = .connected
            self.statusMessage = "Pairing Complete! Connecting Control..."
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.reconnectToControlPort() }
            return
        }
        
        if hex.contains("0802") { // Protocol Version 2
             if let range = hex.range(of: "0802") {
                 let searchHex = String(hex[range.lowerBound...])
                 let statusHex = String(searchHex.dropFirst(4).prefix(6))
                 let payloadHex = String(searchHex.dropFirst(10))
                 
                 if statusHex == "10c801" { // Status 200 OK
                     if payloadHex.hasPrefix("52") || payloadHex.contains("5a") {
                          sendOptions()
                     } else if payloadHex.hasPrefix("a201") {
                          sendConfigurationMessage()
                     } else if payloadHex.hasPrefix("fa01") {
                          Logger.shared.log("Configuration Acknowledged! TV showing code.", category: "Pairing")
                          DispatchQueue.main.async {
                              self.statusMessage = "Enter the code shown on TV"
                              self.isPairing = true
                          }
                     }
                 } else if searchHex.contains("109203") { // Status 402 Bad Secret
                     Logger.shared.log("TV rejected secret (Error 402)", category: "Pairing", type: .error)
                     DispatchQueue.main.async {
                         self.statusMessage = "Error: Bad Secret. Try again."
                         self.isPairing = true
                     }
                 }
             }
        }
    }
    
    private func handleControlPacket(_ data: Data) {
        let msgData = data
        var it = msgData.startIndex
        
        while it < msgData.endIndex {
            let remaining = msgData.subdata(in: it..<msgData.endIndex)
            let (tagAndType, tagBytesRead) = ProtocolBuffer.decodeVarint(remaining)
            if tagBytesRead == 0 { break }
            
            it = msgData.index(it, offsetBy: tagBytesRead)
            
            let tag = Int(tagAndType >> 3)
            let type = Int(tagAndType & 0x07)
            
            if type == 2 { // Length-prefixed
                let lenRemaining = msgData.subdata(in: it..<msgData.endIndex)
                let (len64, lenBytesRead) = ProtocolBuffer.decodeVarint(lenRemaining)
                let len = Int(len64)
                it = msgData.index(it, offsetBy: lenBytesRead, limitedBy: msgData.endIndex) ?? msgData.endIndex
                
                let bodyEnd = msgData.index(it, offsetBy: len, limitedBy: msgData.endIndex) ?? msgData.endIndex
                let body = msgData.subdata(in: it..<bodyEnd)
                
                handleRemoteField(tag: tag, data: body)
                it = bodyEnd
            } else {
                 // Skip other types for now (simplified)
                 if type == 0 { // Varint skip
                     let (_, bytes) = ProtocolBuffer.decodeVarint(msgData.subdata(in: it..<msgData.endIndex))
                     it = msgData.index(it, offsetBy: bytes)
                 } else { // Fixed/Unknown skip
                     break 
                 }
            }
        }
    }
    
    private func handleRemoteField(tag: Int, data: Data) {
        switch tag {
        case 1: // RemoteConfigure
            if !isConfigured {
                var tvCode = 622
                if data.count >= 2 && data[0] == 0x08 {
                    let (val, _) = ProtocolBuffer.decodeVarint(data.dropFirst())
                    tvCode = Int(val)
                }
                sendRemoteConfigAck(code: tvCode)
            }
        case 2: // RemoteConfigureAck
             self.isConfigured = true
             if let ip = self.lastConnectedIP {
                 UserDefaults.standard.set(ip, forKey: lastDeviceIPKey)
             }
             DispatchQueue.main.async {
                 self.statusMessage = "Connected to TV"
                 self.isPairing = false
                 self.connectionState = .connected
             }
        case 8: // PingRequest
             var requestId: Int32 = 1
             if data.count >= 2 && data[0] == 0x08 {
                 let (val, _) = ProtocolBuffer.decodeVarint(data.dropFirst())
                 requestId = Int32(val)
             }
             sendPingResponse(val1: requestId)
        default:
             break
        }
    }

    // MARK: - Actions (Send)
    
    func sendPairingRequest() {
        let info = DeviceInfo(model: "MacBook", vendor: "Apple", unknown1: 1, version: "1.0.0", packageName: "com.google.android.videos.remote", appVersion: "1.0.0")
        var req = PairingRequest(clientName: "atvremote", serviceName: "atvremote")
        req.deviceInfo = info
        let outer = OuterMessage(pairingRequest: req)
        send(outer.serialize())
    }
    
    func sendOptions() {
        let enc = ProtoEncoding(type: 3, symbolLength: 6)
        let opt = Options(inputEncodings: [enc], outputEncodings: [enc], preferredRole: 1)
        let outer = OuterMessage(options: opt)
        send(outer.serialize())
    }
    
    func sendConfigurationMessage() {
        let encoding = ProtoEncoding(type: 3, symbolLength: 6)
        let config = Configuration(encoding: encoding, clientRole: 1)
        let outer = OuterMessage(configuration: config)
        send(outer.serialize())
    }
    
    func sendPairingSecret(_ secret: String) {
        guard let serverCert = serverCertificateData, let serverParams = CryptoUtils.extractRSAParams(from: serverCert),
              let identity = self.identity else {
            Logger.shared.log("Error: Missing params or identity!", category: "Pairing", type: .error)
            return
        }
        
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        guard let c = cert, let clientCertDER = SecCertificateCopyData(c) as Data?,
              let clientParams = CryptoUtils.extractRSAParams(from: clientCertDER) else { return }
        
        // Parse hex secret
        let codeTrailing = String(secret.suffix(4))
        var codeBytes = [UInt8]()
        var sIndex = codeTrailing.startIndex
        while sIndex < codeTrailing.endIndex {
            let nextIndex = codeTrailing.index(sIndex, offsetBy: 2)
            if sIndex < codeTrailing.endIndex && nextIndex <= codeTrailing.endIndex {
                if let byte = UInt8(codeTrailing[sIndex..<nextIndex], radix: 16) {
                    codeBytes.append(byte)
                }
            }
            sIndex = nextIndex
        }
        let codeData = Data(codeBytes)
        
        let (digest, _) = CryptoUtils.getDigest(data: [clientParams.modulus, clientParams.exponent, serverParams.modulus, serverParams.exponent, codeData])
        
        let secretMsg = PairingSecret(secret: digest)
        let outer = OuterMessage(secret: secretMsg)
        
        send(outer.serialize())
        
        // Fallback timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, self.isPairing else { return }
            self.reconnectToControlPort()
        }
    }
    
    func sendKey(_ keycode: Keycode) {
        let pressMsg = RemoteKeyInject(keycode: keycode, direction: .press)
        let pressPkt = RemoteMessage(remoteKeyInject: pressMsg)
        send(pressPkt.serialize())
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let releaseMsg = RemoteKeyInject(keycode: keycode, direction: .release)
            let releasePkt = RemoteMessage(remoteKeyInject: releaseMsg)
            self?.send(releasePkt.serialize())
        }
    }
    
    func send(_ data: Data) {
        var frame = Data()
        let lengthBytes = ProtocolBuffer.encodeVarint(UInt64(data.count))
        frame.append(contentsOf: lengthBytes)
        frame.append(data)
        
        connection?.send(content: frame, completion: .contentProcessed({ error in
             if let error = error {
                 Logger.shared.log("Send error: \(error)", category: "Protocol", type: .error)
             }
        }))
    }
    
    // MARK: - Sleep/Wake
    
    @objc private func onSleep() {
        Logger.shared.log("System Sleep", category: "System")
        self.disconnect()
        self.statusMessage = "Paused (OS Sleeping)"
    }
    
    @objc private func onWake() {
        Logger.shared.log("System Wake", category: "System")
        self.isWakingUp = true
        self.statusMessage = "Resuming connection..."
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            self.isWakingUp = false
            if let ip = self.lastConnectedIP {
                self.triedControlPortFirst = true
                self.connectToIP(host: ip, port: 6466)
            } else {
                self.startDiscovery()
            }
        }
    }
    
    func disconnect() {
        stopPingTimer()
        self.connection?.cancel()
        self.connection = nil
        self.connectionState = .disconnected
    }
    
    // MARK: - Internal Helpers
    
    private func startPingTimer() {
        stopPingTimer()
        DispatchQueue.main.async {
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() {
        // Implementation disabled intentionally on V2
    }
    
    private func reconnectToControlPort() {
        self.connection?.cancel()
        self.connection = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if let ip = self.lastConnectedIP {
                self.connectToIP(host: ip, port: 6466)
            } else if let lastHost = self.netService?.hostName {
                self.connectToIP(host: lastHost, port: 6466)
            } else {
                 self.startDiscovery()
            }
        }
    }
    
    func sendRemoteConfigAck(code: Int) {
        let info = DeviceInfo(model: "MacBook", vendor: "Apple", unknown1: 1, version: "1.0.0", packageName: "com.google.android.videos.remote", appVersion: "1.0.0")
        let config = RemoteConfigure(code1: code, deviceInfo: info)
        let msg = RemoteMessage(remoteConfigureAck: config)
        send(msg.serialize())
    }
    
    func sendPingResponse(val1: Int32) {
        let resp = PingResponse(val1: val1)
        let msg = RemoteMessage(pingResponse: resp)
        send(msg.serialize())
    }
    
    func sendRemoteConfig() {
        let info = DeviceInfo(model: "MacBook", vendor: "Apple", unknown1: 1, version: "1.0.0", packageName: "com.google.android.videos.remote", appVersion: "1.0.0")
        let config = RemoteConfigure(code1: 622, deviceInfo: info)
        let msg = RemoteMessage(remoteConfigure: config)
        send(msg.serialize())
    }
}

// NetService Delegate
extension NetworkManager: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let data = sender.addresses?.first {
            let (ip, _) = extractIPPort(from: data as Data)
            if let ip = ip {
                self.lastConnectedIP = ip
                if self.identity != nil {
                    self.triedControlPortFirst = true
                    connectToIP(host: ip, port: 6466)
                } else {
                    connectToIP(host: ip, port: 6467)
                }
            }
        }
    }
    
    private func extractIPPort(from data: Data) -> (String?, Int?) {
        var storage = sockaddr_in()
        let size = MemoryLayout<sockaddr_in>.size
        _ = withUnsafeMutableBytes(of: &storage) { buffer in
            data.copyBytes(to: buffer, count: size)
        }
        let ip = String(cString: inet_ntoa(storage.sin_addr))
        let port = Int(storage.sin_port.byteSwapped)
        return (ip, port)
    }
}
