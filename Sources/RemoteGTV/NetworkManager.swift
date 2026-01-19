import Foundation
import Network
import Security
import Combine
import CryptoKit
import AppKit // For NSWorkspace

class NetworkManager: NSObject, ObservableObject {
    static let shared = NetworkManager()
    
    // Published states for UI
    @Published var connectionState: ConnectionState = .disconnected
    @Published var statusMessage: String = "Initializing..."
    @Published var discoveredDevices: [NWBrowser.Result] = []
    @Published var isPairing: Bool = false
    
    private var browser: NWBrowser?
    private var isConfigured: Bool = false
    private var connection: NWConnection?
    private var identity: SecIdentity?
    private var serverCertificateData: Data?
    
    private var currentPort: Int = 0
    private var lastConnectedIP: String?
    private var pingTimer: Timer?
    private var receiveBuffer = Data()
    private var triedControlPortFirst: Bool = false
    
    // Sleep/Wake Handling
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
        
        // Setup Sleep/Wake Observers
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onWake), name: NSWorkspace.didWakeNotification, object: nil)
        
        // Load identity on start
        if let cert = CertUtils.shared.loadIdentityFromP12() {
            self.identity = cert
            Logger.shared.log("Certificate loaded successfully.", category: "Network")
            
            // Try to auto-connect to last device if we have a saved IP
            if let savedIP = UserDefaults.standard.string(forKey: lastDeviceIPKey) {
                Logger.shared.log("Found saved device IP: \(savedIP). Auto-connecting...", category: "Network")
                self.lastConnectedIP = savedIP
                self.triedControlPortFirst = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.connectToIP(host: savedIP, port: 6466)
                }
                return
            }
        } else {
            Logger.shared.log("No certificate found. Will need to generate or pair.", category: "Network", type: .error)
        }
        
        startDiscovery()
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    @objc private func onSleep() {
        Logger.shared.log("System is going to sleep. Disconnecting...", category: "System")
        self.disconnect()
        // Ensure we are truly disconnected so we don't get error callbacks later
        self.connectionState = .disconnected
        self.statusMessage = "Paused (OS Sleeping)"
    }
    
    @objc private func onWake() {
        Logger.shared.log("System woke up. Waiting 3s for network...", category: "System")
        self.isWakingUp = true
        self.statusMessage = "Resuming connection..."
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            self.isWakingUp = false
            Logger.shared.log("Attempting reconnect after wake...", category: "System")
            
            // Prefer last connected IP
            if let ip = self.lastConnectedIP {
                Logger.shared.log("Wake: Reconnecting to saved IP \(ip) on Control Port 6466", category: "System")
                self.triedControlPortFirst = true
                self.connectToIP(host: ip, port: 6466)
            } else {
                Logger.shared.log("Wake: No saved IP, restarting discovery.", category: "System")
                self.startDiscovery()
            }
        }
    }
    
    func startDiscovery() {
        self.connectionState = .searching
        self.statusMessage = "Searching for Android TVs..."
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_androidtvremote2._tcp", domain: "local.")
        let parameters = NWParameters.tcp
        
        browser = NWBrowser(for: descriptor, using: parameters)
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discoveredDevices = Array(results)
                Logger.shared.log("Discovered \(results.count) devices: \(results.map { $0.endpoint })", category: "Discovery")
            }
        }
        browser?.start(queue: .main)
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
            // Store for later if needed
            self.netService = service
        }
    }
    
    // For net service resolution
    private var netService: NetService?
    
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
        
        // 1. Client Identity
        if let identity = self.identity {
            sec_protocol_options_set_local_identity(options.securityProtocolOptions, sec_identity_create(identity)!)
            Logger.shared.log("mTLS Identity attached to connection options.", category: "Connection")
        }
        
        // 2. Server Trust
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { (sec_protocol_metadata, sec_trust, sec_protocol_verify_complete) in
            let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()
            
            // Capture the leaf certificate data for pairing hash
            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first {
                self.serverCertificateData = SecCertificateCopyData(certificate) as Data
                Logger.shared.log("Captured Server Certificate (\(self.serverCertificateData?.count ?? 0) bytes)", category: "Connection")
            }
            
            sec_protocol_verify_complete(true)
        }, .global())
        
        let parameters = NWParameters(tls: options)
        parameters.includePeerToPeer = false // Better for local infrastructure
        
        return parameters
    }
    
    private func handleStateUpdate(_ state: NWConnection.State) {
        Logger.shared.log("Connection state changed: \(state)", category: "Connection")
        switch state {
        case .ready:
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
            
        case .failed(let error):
            Logger.shared.log("Connection FAILED: \(error)", category: "Connection", type: .error)
            
            // If Control Port (6466) fails, retry it. DO NOT fallback to 6467 (Pairing) automatically.
            // This prevents "Enter Code" prompts when Wi-Fi is toggled or network is transiently lost.
            if self.currentPort == 6466 {
                Logger.shared.log("Control port connection failed. Retrying 6466 in 2.0s...", category: "Connection")
                self.statusMessage = "Connection lost. Retrying..."
                self.connection?.cancel()
                self.connection = nil
                self.stopPingTimer()
                
                if let ip = self.lastConnectedIP {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self = self else { return }
                        // Check if we haven't started something else in the meantime
                        if self.connectionState != .connected && self.connectionState != .connecting {
                            self.connectToIP(host: ip, port: 6466)
                        }
                    }
                    return
                }
            }
            
            // For other ports (like 6467 failing) or if no IP known:
            self.connectionState = .error(error.localizedDescription)
            self.statusMessage = "Connection failed: \(error.localizedDescription)"
            self.stopPingTimer()
            
        case .cancelled:
            Logger.shared.log("Connection CANCELLED.", category: "Connection")
            self.connectionState = .disconnected
            self.stopPingTimer()
            
        case .preparing:
            Logger.shared.log("Connection PREPARING...", category: "Connection")
            
        default:
            break
        }
    }
    
    private func receiveNextMessage() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                if case .posix(let code) = error, code == .ECANCELED {
                    return
                }
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
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if isComplete {
                    Logger.shared.log("Connection closed by peer (EOF)", category: "Protocol")
                    self.connectionState = .disconnected
                }
                return
            }
            
            self.receiveBuffer.append(data)
            self.processBuffer()
            
            if !isComplete {
                self.receiveNextMessage()
            }
        }
    }
    
    private func processBuffer() {
        while !receiveBuffer.isEmpty {
            let (length64, bytesRead) = ProtocolBuffer.decodeVarint(receiveBuffer)
            let length = Int(length64)
            
            if bytesRead == 0 {
                // Not enough data to even read the length varint
                return
            }
            
            let totalNeeded = bytesRead + length
            if receiveBuffer.count < totalNeeded {
                // We have the length but not the full body yet
                return
            }
            
            // Extract the message body
            let bodyStart = receiveBuffer.index(receiveBuffer.startIndex, offsetBy: bytesRead)
            let bodyEnd = receiveBuffer.index(bodyStart, offsetBy: length)
            let bodyData = receiveBuffer.subdata(in: bodyStart..<bodyEnd)
            
            // Remove processed chunk from buffer
            receiveBuffer.removeSubrange(receiveBuffer.startIndex..<bodyEnd)
            
            // Handle the packet
            self.handlePacket(bodyData)
        }
    }
    private func handlePacket(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        Logger.shared.log("RX RAW (\(data.count) bytes): \(hex.prefix(200))", category: "Protocol")
        
        // Polo v2 OuterMessage parsing (Pairing Port 6467)
        if self.currentPort == 6467 {
            // Check for SecretAck (Tag 41)
            if hex.contains("ca02") {
                Logger.shared.log("Secret Acknowledged! Pairing SUCCESS.", category: "Pairing")
                self.isPairing = false
                self.connectionState = .connected
                self.statusMessage = "Pairing Complete! Connecting Control..."
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.reconnectToControlPort()
                }
                return
            }
            
            if hex.contains("0802") {
                // Find where 0802 starts
                var searchHex = hex
                if let range = hex.range(of: "0802") {
                    searchHex = String(hex[range.lowerBound...])
                }
                
                let statusHex = String(searchHex.dropFirst(4).prefix(6))
                let payloadHex = String(searchHex.dropFirst(10))
                
                if statusHex == "10c801" { // Status 200 OK
                    if payloadHex.hasPrefix("52") || payloadHex.contains("5a") { // PairingRequestAck
                         Logger.shared.log("Detected Pairing Request Ack", category: "Pairing")
                         sendOptions()
                    } else if payloadHex.hasPrefix("a201") { // Options
                         Logger.shared.log("Detected Options", category: "Pairing")
                         sendConfigurationMessage()
                    } else if payloadHex.hasPrefix("fa01") { // ConfigurationAck
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
        // Remote Control Message (Port 6466)
        else if self.currentPort == 6466 {
            let msgData = data
            var it = msgData.startIndex
            
            while it < msgData.endIndex {
                let remaining = msgData.subdata(in: it..<msgData.endIndex)
                let (tagAndType, tagBytesRead) = ProtocolBuffer.decodeVarint(remaining)
                if tagBytesRead == 0 { break }
                
                it = msgData.index(it, offsetBy: tagBytesRead)
                
                let tag = Int(tagAndType >> 3)
                let type = Int(tagAndType & 0x07)
                
                if type == 0 { // Varint
                    let bodyRemaining = msgData.subdata(in: it..<msgData.endIndex)
                    let (_, bodyBytesRead) = ProtocolBuffer.decodeVarint(bodyRemaining)
                    it = msgData.index(it, offsetBy: bodyBytesRead, limitedBy: msgData.endIndex) ?? msgData.endIndex
                } else if type == 2 { // Length-prefixed
                    let lenRemaining = msgData.subdata(in: it..<msgData.endIndex)
                    let (len64, lenBytesRead) = ProtocolBuffer.decodeVarint(lenRemaining)
                    let len = Int(len64)
                    
                    it = msgData.index(it, offsetBy: lenBytesRead, limitedBy: msgData.endIndex) ?? msgData.endIndex
                    
                    // Ensure we don't go out of bounds
                    let bodyEnd = msgData.index(it, offsetBy: len, limitedBy: msgData.endIndex) ?? msgData.endIndex
                    
                    let body = msgData.subdata(in: it..<bodyEnd)
                    handleRemoteField(tag: tag, data: body)
                    
                    it = bodyEnd
                } else if type == 1 { // Fixed64
                    it = msgData.index(it, offsetBy: 8, limitedBy: msgData.endIndex) ?? msgData.endIndex
                } else if type == 5 { // Fixed32
                    it = msgData.index(it, offsetBy: 4, limitedBy: msgData.endIndex) ?? msgData.endIndex
                } else {
                    it = msgData.endIndex 
                }
            }
        }
    }
    
    private func handleRemoteField(tag: Int, data: Data) {
        switch tag {
        case 1: // RemoteConfigure from TV
            if isConfigured {
                Logger.shared.log("TV sent another Configuration. Ignoring since already configured.", category: "Protocol")
                return
            }
            Logger.shared.log("TV sent Configuration. Acknowledging...", category: "Protocol")
            var tvCode = 622
            if data.count >= 2 && data[0] == 0x08 {
                let (val, _) = ProtocolBuffer.decodeVarint(data.dropFirst())
                tvCode = Int(val)
                Logger.shared.log("Captured TV Configuration Code: \(tvCode)", category: "Protocol")
            }
            sendRemoteConfigAck(code: tvCode)
        case 2: // RemoteConfigureAck
            Logger.shared.log("Remote Control Configured and READY!", category: "Network")
            self.isConfigured = true
            
            // Save the IP for auto-connect next time
            if let ip = self.lastConnectedIP {
                UserDefaults.standard.set(ip, forKey: lastDeviceIPKey)
                Logger.shared.log("Saved device IP for auto-connect: \(ip)", category: "Network")
            }
            
            DispatchQueue.main.async {
                self.statusMessage = "Connected to TV"
                self.isPairing = false
                self.connectionState = .connected
            }
        case 3: // RemoteStatus / Echo / KeyEcho
            Logger.shared.log("TV sent Status/Echo (Tag 3)", category: "Protocol")
        case 8: // PingRequest from TV
            Logger.shared.log("TV Pinged us (Tag 8). Responding...", category: "Protocol")
            var requestId: Int32 = 1
            if data.count >= 2 && data[0] == 0x08 {
                let (val, _) = ProtocolBuffer.decodeVarint(data.dropFirst())
                requestId = Int32(val)
            }
            sendPingResponse(val1: requestId)
        case 12: // AppInfo (Old style) or state data
            Logger.shared.log("TV App Info: \(data.count) bytes", category: "Protocol")
        case 20: // Current App Info
            Logger.shared.log("TV Current App Update: \(data.count) bytes", category: "Protocol")
        case 24: // Power Status
            Logger.shared.log("TV Power/Status update (Tag 24)", category: "Protocol")
        case 50: // Detailed App/State info
            Logger.shared.log("TV Detailed State update (Tag 50)", category: "Protocol")
        default:
            let hex = data.map { String(format: "%02x", $0) }.joined()
            Logger.shared.log("Tag \(tag) not explicitly handled (Len: \(data.count)): \(hex.prefix(40))", category: "Protocol")
        }
    }

    
    // MARK: - Actions
    
    func sendPairingRequest() {
        Logger.shared.log("Sending Pairing Request...", category: "Pairing")
        let info = DeviceInfo(model: "MacBook", vendor: "Apple", unknown1: 1, version: "1.0.0", packageName: "com.google.android.videos.remote", appVersion: "1.0.0")
        var req = PairingRequest(clientName: "atvremote", serviceName: "atvremote")
        req.deviceInfo = info
        
        let outer = OuterMessage(pairingRequest: req)
        send(outer.serialize())
    }
    
    func sendOptions() {
        Logger.shared.log("Sending Options...", category: "Pairing")
        let enc = ProtoEncoding(type: 3, symbolLength: 6)
        let opt = Options(inputEncodings: [enc], outputEncodings: [enc], preferredRole: 1)
        let outer = OuterMessage(options: opt)
        send(outer.serialize())
    }
    
    func sendConfigurationMessage() {
        Logger.shared.log("Sending Configuration...", category: "Pairing")
        let encoding = ProtoEncoding(type: 3, symbolLength: 6)
        let config = Configuration(encoding: encoding, clientRole: 1)
        
        let outer = OuterMessage(configuration: config)
        send(outer.serialize())
    }
    

    
    func sendPairingSecret(_ secret: String) {
        Logger.shared.log("Calculating SHA256 for secret: \(secret)", category: "Pairing")
        
        guard let serverCert = serverCertificateData, let serverParams = CryptoUtils.extractRSAParams(from: serverCert),
              let identity = self.identity else {
            Logger.shared.log("Error: Missing params or identity!", category: "Pairing", type: .error)
            return
        }
        
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        guard let c = cert, let clientCertDER = SecCertificateCopyData(c) as Data?,
              let clientParams = CryptoUtils.extractRSAParams(from: clientCertDER) else {
            Logger.shared.log("Error: Could not extract Client RSA Params!", category: "Pairing", type: .error)
            return
        }
        
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
        
        let codeHeader = secret.prefix(2).uppercased()
        let codeData = Data(codeBytes)
        
        // Primary probe
        let (digest, header) = CryptoUtils.getDigest(data: [clientParams.modulus, clientParams.exponent, serverParams.modulus, serverParams.exponent, codeData])
        Logger.shared.log("Hash header: \(header) vs \(codeHeader)", category: "Pairing")
        
        // We will send 32 bytes because 31 gave 402. 
        // If the TV is silent but code disappears, it often means success.
        let secretMsg = PairingSecret(secret: digest) 
        let outer = OuterMessage(secret: secretMsg)
        
        Logger.shared.log("Sending 32-byte secret to TV...", category: "Pairing")
        send(outer.serialize())
        
        // Fallback: If no response in 3 seconds, assume maybe it worked or try 31 bytes
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, self.isPairing else { return }
            Logger.shared.log("No response after 3s. Attempting to switch to control port anyway...", category: "Pairing")
            self.reconnectToControlPort()
        }
    }
    
    func sendKey(_ keycode: Keycode) {
        Logger.shared.log("Sending key: \(keycode)", category: "Protocol")
        
        // Per wiki docs: send press (16,1) then release (16,2)
        let pressMsg = RemoteKeyInject(keycode: keycode, direction: .press)
        let pressPkt = RemoteMessage(remoteKeyInject: pressMsg)
        send(pressPkt.serialize())
        
        // Send release after small delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let releaseMsg = RemoteKeyInject(keycode: keycode, direction: .release)
            let releasePkt = RemoteMessage(remoteKeyInject: releaseMsg)
            self?.send(releasePkt.serialize())
        }
    }
    
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
        // Proactive pings disabled - the Mi TV Stick returns error code 5 (INVALID_ARGUMENT)
        // when we send pings. We only respond to TV-initiated pings instead.
    }
    
    private func reconnectToControlPort() {
        Logger.shared.log("Switching to Control Port 6466 in 2 seconds...", category: "Network")
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
    
    func sendRemoteConfig() {
        Logger.shared.log("Sending Remote Configuration (v2)...", category: "Connection")
        let info = DeviceInfo(model: "MacBook", vendor: "Apple", unknown1: 1, version: "1.0.0", packageName: "com.google.android.videos.remote", appVersion: "1.0.0")
        let config = RemoteConfigure(code1: 622, deviceInfo: info)
        let msg = RemoteMessage(remoteConfigure: config)
        send(msg.serialize())
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

    func send(_ data: Data) {
        var frame = Data()
        // Polo v2 uses standard length-delimited protobuf on both ports.
        // The version byte (0x01/0x02/0x04) is NOT used in the modern version.
        let lengthBytes = ProtocolBuffer.encodeVarint(UInt64(data.count))
        frame.append(contentsOf: lengthBytes)
        frame.append(data)
        
        Logger.shared.log("TX (\(self.currentPort)): Sending \(data.count) payload bytes: \(frame.map { String(format: "%02x", $0) }.joined())", category: "Protocol")
        
        connection?.send(content: frame, completion: .contentProcessed({ error in
            if let error = error {
                Logger.shared.log("Send error: \(error)", category: "Protocol", type: .error)
            }
        }))
    }
    
    func disconnect() {
        stopPingTimer()
        self.connection?.cancel()
        self.connection = nil
        self.connectionState = .disconnected
    }
}

extension NetworkManager: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let data = sender.addresses?.first {
            let (ip, port) = extractIPPort(from: data as Data)
            if let ip = ip {
                self.lastConnectedIP = ip
                
                // If we have a certificate, try control port first (already paired)
                if self.identity != nil {
                    Logger.shared.log("Resolved IPv4: \(ip) - Certificate exists, trying control port 6466 first", category: "Discovery")
                    self.triedControlPortFirst = true
                    connectToIP(host: ip, port: 6466)
                } else {
                    // No certificate, need to pair first
                    Logger.shared.log("Resolved IPv4: \(ip) - No certificate, going to pairing port 6467", category: "Discovery")
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
