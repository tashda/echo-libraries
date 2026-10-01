import Foundation
import Security
import Testing
@testable import EchoKerberos
@testable import EchoTLS

@Suite("TrustBundle and ServerTrust")
struct TrustTests {
    @Test func bundleHoldsTheSystemRoots() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "EchoTLSTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try TrustBundle.refresh(in: directory)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let certificates = text.components(separatedBy: "-----BEGIN CERTIFICATE-----").count - 1
        var anchors: CFArray?
        _ = SecTrustCopyAnchorCertificates(&anchors)
        #expect(certificates >= ((anchors as? [SecCertificate])?.count ?? 0) - 5, "system roots, minus any the user distrusts")
        #expect(certificates > 50)
        #expect(try TrustBundle.currentPath(in: directory) == path)
        #expect(try TrustBundle.refresh(in: directory) == path, "same trust, same file")
    }

    @Test func trustSettingsVerdicts() {
        let ssl = SecPolicyCreateSSL(true, nil)
        let basic = SecPolicyCreateBasicX509()
        let deny = NSNumber(value: SecTrustSettingsResult.deny.rawValue)
        let asRoot = NSNumber(value: SecTrustSettingsResult.trustAsRoot.rawValue)
        let unspecified = NSNumber(value: SecTrustSettingsResult.unspecified.rawValue)
        let result = kSecTrustSettingsResult as String, policy = kSecTrustSettingsPolicy as String
        #expect(TrustBundle.verdict(forConstraints: []) == .trusted)
        #expect(TrustBundle.verdict(forConstraints: [[policy: ssl]]) == .trusted)
        #expect(TrustBundle.verdict(forConstraints: [[policy: ssl, result: asRoot]]) == .trusted)
        #expect(TrustBundle.verdict(forConstraints: [[policy: ssl, result: deny]]) == .distrusted)
        #expect(TrustBundle.verdict(forConstraints: [[policy: ssl, result: asRoot], [result: deny]]) == .distrusted)
        #expect(TrustBundle.verdict(forConstraints: [[policy: basic, result: asRoot]]) == .unspecified)
        #expect(TrustBundle.verdict(forConstraints: [[policy: ssl, result: unspecified]]) == .unspecified)
        #expect(TrustBundle.verdict(forConstraints: [[policy: ssl, kSecTrustSettingsPolicyString as String: "db.example.com"]]) == .unspecified)
    }

    @Test func serverTrust() throws {
        let fixtures = try CertificateFixtures()
        defer { fixtures.remove() }
        let server = try #require(FileManager.default.contents(atPath: fixtures.path("server.der")))
        let ca = try ServerTrust.certificates(inPEMFile: fixtures.path("ca.pem"))
        #expect(ca.count == 1)
        #expect(ServerTrust.evaluate(chain: [server], host: "db.echo.test", anchors: ca) == .trusted)
        #expect(ServerTrust.evaluate(chain: [server], host: nil, anchors: ca) == .trusted)
        if case .trusted = ServerTrust.evaluate(chain: [server], host: "other.echo.test", anchors: ca) {
            Issue.record("a certificate for another host was trusted")
        }
        if case .trusted = ServerTrust.evaluate(chain: [server], host: "db.echo.test") {
            Issue.record("a CA macOS doesn't trust was trusted")
        }
        #expect(ServerTrust.evaluate(chain: [], host: "db.echo.test") != .trusted)
    }

    @Test func derClassification() throws {
        let fixtures = try CertificateFixtures()
        defer { fixtures.remove() }
        let cases: [(String, PrivateKeyFormat)] = [
            ("rsa-pkcs1.der", .rsa), ("rsa-pkcs8.der", .pkcs8), ("rsa-encrypted.der", .encryptedPKCS8), ("ec-sec1.der", .ec),
        ]
        for (file, format) in cases {
            let data = try #require(FileManager.default.contents(atPath: fixtures.path(file)))
            #expect(PrivateKeyFormat(der: data) == format, "\(file)")
        }
        let certificate = try #require(FileManager.default.contents(atPath: fixtures.path("rsa.der")))
        #expect(PrivateKeyFormat(der: certificate) == nil)
    }

    @Test func kerberosTicketReadsTheCache() {
        // Whatever the machine has: it must answer without asking the KDC or crashing.
        switch KerberosTicket.current() {
        case .valid(let principal, _): #expect(principal.contains("@"))
        case .expired, .none: break
        case .unavailable: Issue.record("GSS.framework is always there on macOS")
        }
    }
}
