import Foundation
import Security

/// A second opinion from macOS on a server's certificate chain, after OpenSSL accepted it during
/// the handshake and before any query is sent. It catches what OpenSSL can't know: certificates
/// the user marked "Never Trust" in Keychain Access, and the rest of macOS's TLS policy.
///
/// `SecTrustEvaluateWithError` can block (it may fetch intermediates or revocation data), so call
/// this off the main actor.
public enum ServerTrust {
    public enum Verdict: Sendable, Equatable {
        case trusted
        /// macOS rejected the chain; the reason in macOS's words.
        case rejected(String)
    }

    /// - Parameters:
    ///   - chain: the server's certificates in DER, its own first.
    ///   - host: the name to check the certificate against; nil checks the chain only
    ///     (libpq `verify-ca`).
    ///   - anchors: the CA certificates (DER) the user chose for this connection; only they are
    ///     trusted then. Nil trusts what macOS trusts.
    public static func evaluate(chain: [Data], host: String?, anchors: [Data]? = nil) -> Verdict {
        let certificates = chain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard !certificates.isEmpty, certificates.count == chain.count else {
            return .rejected("The server sent no readable certificate.")
        }
        let policy = SecPolicyCreateSSL(true, host as CFString?)
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess, let trust else {
            return .rejected("macOS could not evaluate the server's certificate.")
        }
        if let anchors {
            let anchorCertificates = anchors.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            SecTrustSetAnchorCertificates(trust, anchorCertificates as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
        }
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) { return .trusted }
        let reason = error.map { CFErrorCopyDescription($0) as String } ?? "macOS does not trust the server's certificate."
        return .rejected(reason)
    }

    /// The certificates in a PEM file (a CA file the user chose), in DER.
    public static func certificates(inPEMFile path: String) throws -> [Data] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return PEM.blocks(in: text, label: "CERTIFICATE")
    }
}
