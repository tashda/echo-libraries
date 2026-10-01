import Foundation
import Security

/// The certificate chain and private key of a `.p12`/`.pfx` file, read by Security.framework
/// (which also reads the legacy RC2/3DES files OpenSSL 3 only opens with its legacy provider) and
/// written out as PEM.
struct PKCS12Contents {
    /// The client certificate first, then any CA certificates in the file.
    let certificatesPEM: String
    let keyPEM: String

    static func read(_ data: Data, password: String?) -> Result<PKCS12Contents, ClientCertificateError> {
        var items: CFArray?
        // Known gap: Security.framework computes the MAC of an empty password differently from
        // OpenSSL, so a file OpenSSL exported with an empty password fails here (errSecAuthFailed).
        let status = importBundle(data, password: password ?? "", into: &items)
        if status == errSecAuthFailed || status == errSecPkcs12VerifyFailure {
            return .failure(password?.isEmpty == false
                ? ClientCertificateError(kind: .wrongKeyPassword, message: "The password does not open the certificate file.")
                : ClientCertificateError(kind: .keyNeedsPassword, message: "The certificate file is protected by a password. Enter the key password. A .p12 file exported with an empty password can't be opened: export it again with a password, or as PEM files."))
        }
        guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
              let identityValue = first[kSecImportItemIdentity as String] else {
            return .failure(ClientCertificateError(kind: .unreadable, message: "The file is not a certificate bundle with a private key (\(status))."))
        }
        // CF types can't be cast conditionally; SecPKCS12Import documents this key as a SecIdentity.
        let identity = identityValue as! SecIdentity
        var certificate: SecCertificate?
        var key: SecKey?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
              SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess, let key else {
            return .failure(ClientCertificateError(kind: .unreadable, message: "The certificate bundle has no usable certificate and key."))
        }
        let leaf = SecCertificateCopyData(certificate) as Data
        let chain = (first[kSecImportItemCertChain as String] as? [SecCertificate] ?? [])
            .map { SecCertificateCopyData($0) as Data }
            .filter { $0 != leaf }
        let certificatesPEM = ([leaf] + chain).map { PEM.encode($0, label: "CERTIFICATE") }.joined()
        return privateKeyPEM(key).map { PKCS12Contents(certificatesPEM: certificatesPEM, keyPEM: $0) }
    }

    private static func importBundle(_ data: Data, password: String, into items: inout CFArray?) -> OSStatus {
        let options: [String: Any] = [kSecImportToMemoryOnly as String: true, kSecImportExportPassphrase as String: password]
        return SecPKCS12Import(data as CFData, options as CFDictionary, &items)
    }

    /// RSA keys export as PKCS#1, which OpenSSL reads as is. EC keys export as X9.63
    /// (`04 || X || Y || K`) and are wrapped into SEC1 `ECPrivateKey`.
    static func privateKeyPEM(_ key: SecKey) -> Result<String, ClientCertificateError> {
        var error: Unmanaged<CFError>?
        guard let exported = SecKeyCopyExternalRepresentation(key, &error) as Data?,
              let attributes = SecKeyCopyAttributes(key) as? [String: Any],
              let type = attributes[kSecAttrKeyType as String] as? String else {
            _ = error?.takeRetainedValue()
            return .failure(ClientCertificateError(kind: .unsupportedKey, message: "The private key in the certificate file can't be exported."))
        }
        if type == (kSecAttrKeyTypeRSA as String) {
            return .success(PEM.encode(exported, label: "RSA PRIVATE KEY"))
        }
        if type == (kSecAttrKeyTypeECSECPrimeRandom as String), let sec1 = ecPrivateKey(x963: exported) {
            return .success(PEM.encode(sec1, label: "EC PRIVATE KEY"))
        }
        return .failure(ClientCertificateError(kind: .unsupportedKey, message: "The certificate file holds a key type Echo can't use (only RSA and EC P-256, P-384, P-521)."))
    }

    /// SEC1: SEQUENCE { INTEGER 1, OCTET STRING k, [0] curve OID, [1] BIT STRING public key }.
    static func ecPrivateKey(x963: Data) -> Data? {
        let curves: [Int: [UInt8]] = [
            32: [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07], // P-256
            48: [0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x22],                   // P-384
            66: [0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x23],                   // P-521
        ]
        // 1 + 2n (public point) + n (scalar)
        guard x963.first == 0x04, (x963.count - 1) % 3 == 0 else { return nil }
        let size = (x963.count - 1) / 3
        guard let oid = curves[size] else { return nil }
        let publicKey = x963.prefix(1 + 2 * size)
        let scalar = x963.suffix(size)
        var body = DERElement.encode(tag: 0x02, Data([1]))
        body += DERElement.encode(tag: 0x04, Data(scalar))
        body += DERElement.encode(tag: 0xA0, Data(oid))
        body += DERElement.encode(tag: 0xA1, DERElement.encode(tag: 0x03, Data([0]) + publicKey))
        return DERElement.encode(tag: 0x30, body)
    }
}
