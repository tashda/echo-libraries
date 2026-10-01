import Foundation
import Security

/// Questions a sign-in sheet asks about client-certificate files before connecting.
public enum ClientCertificate {
    /// Whether the path names a PKCS#12 file, which holds the certificate and the key together.
    public static func isPKCS12(_ path: String) -> Bool {
        ["p12", "pfx"].contains((path as NSString).pathExtension.lowercased())
    }

    /// Whether the key file (or PKCS#12 file) needs a password to be opened. PEM files are read by
    /// their header (`ENCRYPTED PRIVATE KEY`, `Proc-Type: 4,ENCRYPTED`), DER files by their
    /// structure, PKCS#12 files are tried with an empty password. False when the file can't be read.
    public static func keyNeedsPassword(atPath path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path) else { return false }
        if isPKCS12(path) {
            if case .failure(let error) = PKCS12Contents.read(data, password: nil) {
                return error.kind == .keyNeedsPassword
            }
            return false
        }
        if PEM.isPEM(data) {
            let text = String(decoding: data, as: UTF8.self)
            return text.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----") || text.contains("Proc-Type: 4,ENCRYPTED")
        }
        return PrivateKeyFormat(der: data) == .encryptedPKCS8
    }
}
