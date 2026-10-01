import CryptoKit
import Foundation
import Security
import Synchronization

/// The certificate authorities this Mac trusts for TLS servers, as a PEM file for OpenSSL
/// (libpq `sslrootcert`, MariaDB `MYSQL_OPT_SSL_CA`), which doesn't read the Keychain itself.
///
/// The bundle holds the system roots plus every certificate the admin or user trust settings
/// trust for SSL (company CAs installed by IT or MDM, ones the user trusted in Keychain Access),
/// minus every certificate those settings distrust. Trust limited to one host or one application
/// is left out: the bundle is used for every server.
public enum TrustBundle {
    /// `~/Library/Application Support/Echo/TLS`.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Echo/TLS", directoryHint: .isDirectory)
    }

    private static let cache = Mutex<[String: String]>([:])

    /// The bundle's path, written on first use. Later calls reuse it until `refresh(in:)`.
    public static func currentPath(in directory: URL = defaultDirectory) throws -> String {
        if let path = cache.withLock({ $0[directory.path] }), FileManager.default.fileExists(atPath: path) {
            return path
        }
        return try refresh(in: directory)
    }

    /// Reads the Keychain's trust again and writes a new bundle when it changed (for example when
    /// the app becomes active). Returns the current path.
    @discardableResult
    public static func refresh(in directory: URL = defaultDirectory) throws -> String {
        let pem = trustedCertificates().map { PEM.encode(SecCertificateCopyData($0) as Data, label: "CERTIFICATE") }.joined()
        let data = Data(pem.utf8)
        let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        let file = directory.appending(path: "trust-\(digest).pem")
        if !FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        }
        removeOldBundles(in: directory, keeping: file)
        cache.withLock { $0[directory.path] = file.path }
        return file.path
    }

    /// System roots plus admin and user trust, minus distrust; each certificate once.
    static func trustedCertificates() -> [SecCertificate] {
        var anchors: CFArray?
        var certificates = SecTrustCopyAnchorCertificates(&anchors) == errSecSuccess
            ? (anchors as? [SecCertificate]) ?? [] : []
        var verdicts: [Data: TrustVerdict] = [:]
        // The user domain overrides the admin domain.
        for domain in [SecTrustSettingsDomain.admin, .user] {
            for certificate in certificatesWithTrustSettings(in: domain) {
                let verdict = verdict(for: certificate, in: domain)
                guard verdict != .unspecified else { continue }
                verdicts[SecCertificateCopyData(certificate) as Data] = verdict
                if verdict == .trusted { certificates.append(certificate) }
            }
        }
        var seen = Set<Data>()
        return certificates.filter { certificate in
            let der = SecCertificateCopyData(certificate) as Data
            return verdicts[der] != .distrusted && seen.insert(der).inserted
        }
    }

    enum TrustVerdict { case trusted, distrusted, unspecified }

    private static func certificatesWithTrustSettings(in domain: SecTrustSettingsDomain) -> [SecCertificate] {
        var list: CFArray?
        guard SecTrustSettingsCopyCertificates(domain, &list) == errSecSuccess else { return [] }
        return (list as? [SecCertificate]) ?? []
    }

    private static func verdict(for certificate: SecCertificate, in domain: SecTrustSettingsDomain) -> TrustVerdict {
        var settings: CFArray?
        guard SecTrustSettingsCopyTrustSettings(certificate, domain, &settings) == errSecSuccess,
              let constraints = settings as? [[String: Any]] else { return .unspecified }
        return verdict(forConstraints: constraints)
    }

    /// Combines the usage-constraint dictionaries that apply to every TLS server: an empty list
    /// means "always trust"; a missing result means trust as root; distrust wins over trust.
    static func verdict(forConstraints constraints: [[String: Any]]) -> TrustVerdict {
        if constraints.isEmpty { return .trusted }
        var result = TrustVerdict.unspecified
        for constraint in constraints {
            if constraint[kSecTrustSettingsPolicyString as String] != nil
                || constraint[kSecTrustSettingsApplication as String] != nil { continue }
            if let policy = constraint[kSecTrustSettingsPolicy as String], !isSSLPolicy(policy) { continue }
            let raw = (constraint[kSecTrustSettingsResult as String] as? NSNumber)?.uint32Value
                ?? SecTrustSettingsResult.trustRoot.rawValue
            switch SecTrustSettingsResult(rawValue: raw) {
            case .deny: return .distrusted
            case .trustRoot, .trustAsRoot: result = .trusted
            default: break
            }
        }
        return result
    }

    private static func isSSLPolicy(_ value: Any) -> Bool {
        guard CFGetTypeID(value as CFTypeRef) == SecPolicyGetTypeID() else { return false }
        // CF types can't be cast conditionally; the type ID was checked above.
        let policy = value as! SecPolicy
        guard let properties = SecPolicyCopyProperties(policy) as? [String: Any],
              let oid = properties[kSecPolicyOid as String] as? String else { return false }
        return oid == (kSecPolicyAppleSSL as String)
    }

    /// Bundles from earlier trust states that no connection has needed for a day.
    private static func removeOldBundles(in directory: URL, keeping current: URL) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        let dayAgo = Date().addingTimeInterval(-86_400)
        for name in names where name.hasPrefix("trust-") && name.hasSuffix(".pem") && name != current.lastPathComponent {
            let path = directory.appending(path: name).path
            if let modified = try? manager.attributesOfItem(atPath: path)[.modificationDate] as? Date, modified < dayAgo {
                try? manager.removeItem(atPath: path)
            }
        }
    }
}
