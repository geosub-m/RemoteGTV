import Foundation
import Security
import CryptoKit

class CryptoUtils {
    
    /// Calculate SHA256 digest of concatenated data parts, returning (bytes, hexString)
    static func getDigest(data: [Data]) -> (Data, String) {
        var hasher = SHA256()
        for d in data { hasher.update(data: d) }
        let digest = hasher.finalize()
        return (Data(digest), Array(digest).prefix(1).map { String(format: "%02X", $0) }.joined())
    }
    
    /// Extract RSA params (modulus, exponent) from a DER-encoded (or sometimes rough) key data.
    /// This logic attempts to parse a simplified RSA structure.
    static func extractRSAParams(from certData: Data) -> (modulus: Data, exponent: Data)? {
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else { return nil }
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        SecTrustCreateWithCertificates(certificate, policy, &trust)
        
        guard let t = trust, let publicKey = SecTrustCopyKey(t) else { return nil }
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { return nil }
        
        // Basic ASN.1 parsing for RSA Public Key (Sequence)
        // Expected: Sequence { Integer(Modulus), Integer(Exponent) }
        
        var offset = 0
        if offset >= keyData.count || keyData[offset] != 0x30 { return nil } // Sequence
        offset += 1
        
        // Length of sequence
        if offset >= keyData.count { return nil }
        if keyData[offset] & 0x80 != 0 {
            let lenSize = Int(keyData[offset] & 0x7F)
            offset += 1 + lenSize
        } else {
            offset += 1
        }
        
        // Integer (Modulus)
        if offset >= keyData.count || keyData[offset] != 0x02 { return nil }
        offset += 1
        
        var modLen: Int = 0
        if offset >= keyData.count { return nil }
        if keyData[offset] & 0x80 != 0 {
            let lenSize = Int(keyData[offset] & 0x7F)
            offset += 1
            if offset + lenSize > keyData.count { return nil }
            for _ in 0..<lenSize {
                modLen = (modLen << 8) | Int(keyData[offset])
                offset += 1
            }
        } else {
            modLen = Int(keyData[offset])
            offset += 1
        }
        
        var modStart = offset
        var actualModLen = modLen
        
        // If modulus has leading zero (to make it positive), skip it
        if modStart < keyData.count && keyData[modStart] == 0x00 {
            modStart += 1
            actualModLen -= 1
        }
        
        if modStart + actualModLen > keyData.count { return nil }
        let modulus = keyData.subdata(in: modStart..<(modStart + actualModLen))
        offset += modLen
        
        // Integer (Exponent)
        if offset >= keyData.count || keyData[offset] != 0x02 { return nil }
        offset += 1
        
        if offset >= keyData.count { return nil }
        let expLen = Int(keyData[offset])
        offset += 1
        
        if offset + expLen > keyData.count { return nil }
        let exponent = keyData.subdata(in: offset..<(offset + expLen))
        
        return (modulus, exponent)
    }
}
