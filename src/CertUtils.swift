import Foundation
import Security
import CryptoKit

class CertUtils {
    
    static let shared = CertUtils()
    private let kIdentityLabel = "AndroidTVRemoteIdentity"
    
    // Generate or Retrieve a Self-Signed Identity
    func getIdentity() -> SecIdentity? {
        if let existing = loadIdentity() {
            Logger.shared.log("CertUtils: Loaded existing identity from keychain.", category: "Certificates")
            return existing
        }
        
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let p12Path = appSupport.appendingPathComponent("identity.p12").path
        
        if fileManager.fileExists(atPath: p12Path) {
            Logger.shared.log("CertUtils: Loading existing p12 from \(p12Path)", category: "Certificates")
            return loadIdentityFromP12(path: p12Path)
        }
        
        Logger.shared.log("CertUtils: No identity found. Generating new self-signed certificate...", category: "Certificates")
        guard let newIdentity = generateIdentityViaOpenSSL() else {
            Logger.shared.log("CertUtils: Failed to generate identity.", category: "Certificates", type: .error)
            return nil
        }
        
        return newIdentity
    }
    
    // MARK: - Keychain Loading (System)
    private func loadIdentity() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: kIdentityLabel,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess {
            return (item as! SecIdentity)
        }
        return nil
    }
    
    func deleteIdentity() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let p12Path = appSupport.appendingPathComponent("identity.p12").path
        try? fileManager.removeItem(atPath: p12Path)
        Logger.shared.log("Deleted existing identity at \(p12Path)", category: "Certificates")
    }

    // MARK: - OpenSSL Generation & P12 Import
    func generateIdentityViaOpenSSL() -> SecIdentity? {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let keyPath = appSupport.appendingPathComponent("key.pem").path
        let csrPath = appSupport.appendingPathComponent("req.csr").path
        let certPath = appSupport.appendingPathComponent("cert.pem").path
        let p12Path = appSupport.appendingPathComponent("identity.p12").path
        
        // Ensure dir exists
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)

        // Check if p12 exists
        if fileManager.fileExists(atPath: p12Path) {
            Logger.shared.log("Loading p12 from \(p12Path)", category: "Certificates")
            return loadIdentityFromP12(path: p12Path)
        }
        
        Logger.shared.log("Generating new Key/Cert via OpenSSL at \(appSupport.path)", category: "Certificates")
        
        let uniqueName = "atvremote" 
        let configPath = appSupport.appendingPathComponent("openssl.cnf").path
        let configContent = """
        [req]
        distinguished_name = req_distinguished_name
        req_extensions = v3_req
        x509_extensions = v3_req
        prompt = no
        [req_distinguished_name]
        CN = \(uniqueName)
        [v3_req]
        basicConstraints = CA:TRUE, pathlen:0
        subjectAltName = DNS:\(uniqueName)
        """
        try? configContent.write(toFile: configPath, atomically: true, encoding: .utf8)

        // 1. Generate Private Key and CSR
        let reqTask = Process()
        reqTask.launchPath = "/usr/bin/openssl"
        reqTask.arguments = ["req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", keyPath, "-out", csrPath, "-config", configPath]
        reqTask.launch()
        reqTask.waitUntilExit()
        
        if reqTask.terminationStatus != 0 {
             Logger.shared.log("OpenSSL Req CSR failed: \(reqTask.terminationStatus)", category: "Certificates", type: .error)
             return nil
        }
        
        // 2. Sign Certificate with Serial 1000
        let signTask = Process()
        signTask.launchPath = "/usr/bin/openssl"
        signTask.arguments = ["x509", "-req", "-in", csrPath, "-signkey", keyPath, "-out", certPath, "-days", "3650", "-set_serial", "1000", "-extfile", configPath, "-extensions", "v3_req"]
        signTask.launch()
        signTask.waitUntilExit()
        
        if signTask.terminationStatus != 0 {
             Logger.shared.log("OpenSSL Sign failed: \(signTask.terminationStatus)", category: "Certificates", type: .error)
             return nil
        }
        
        // 3. Export to P12
        let exportTask = Process()
        exportTask.launchPath = "/usr/bin/openssl"
        exportTask.arguments = ["pkcs12", "-export", "-out", p12Path, "-inkey", keyPath, "-in", certPath, "-passout", "pass:password"]
        exportTask.launch()
        exportTask.waitUntilExit()
        
        if exportTask.terminationStatus != 0 {
            Logger.shared.log("OpenSSL Export failed with status \(exportTask.terminationStatus)", category: "Certificates", type: .error)
            return nil
        }
        
        // Import P12
        return loadIdentityFromP12(path: p12Path)
    }
    
    func loadIdentityFromP12() -> SecIdentity? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let p12Path = appSupport.appendingPathComponent("identity.p12").path
        return loadIdentityFromP12(path: p12Path)
    }
    
    func loadIdentityFromP12(path: String) -> SecIdentity? {
        guard let p12Data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let options: [String: Any] = [kSecImportExportPassphrase as String: "password"]
        
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        
        if status == errSecSuccess, let items = items as? [[String: Any]], let first = items.first {
            return (first[kSecImportItemIdentity as String] as! SecIdentity)
        }
        
        Logger.shared.log("P12 Import failed: \(status)", category: "Certificates", type: .error)
        return nil
    }
}
