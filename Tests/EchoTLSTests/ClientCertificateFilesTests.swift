import Foundation
import Testing
@testable import EchoTLS

@Suite("ClientCertificateFiles", .serialized)
struct ClientCertificateFilesTests {
    let fixtures: CertificateFixtures
    let root: URL

    init() throws {
        fixtures = try CertificateFixtures()
        root = fixtures.directory.appending(path: "out")
    }

    /// The files OpenSSL gets hold a certificate and the key that belongs to it.
    private func expectMatching(_ files: ClientCertificateFiles, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let certificateKey = try CertificateFixtures.publicKey(certificate: files.certificatePath)
        let key = try CertificateFixtures.publicKey(key: files.keyPath, password: files.keyPassword)
        #expect(certificateKey == key, sourceLocation: sourceLocation)
    }

    private func permissions(_ path: String) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
    }

    @Test(arguments: [
        ("rsa.pem", "rsa.key"),
        ("rsa.pem", "rsa-pkcs8.key"),
        ("rsa.der", "rsa-pkcs1.der"),
        ("rsa.der", "rsa-pkcs8.der"),
        ("ec-prime256v1.pem", "ec-prime256v1.key"),
        ("ec-prime256v1.pem", "ec-sec1.der"),
    ])
    func unencryptedForms(certificate: String, key: String) throws {
        let files = try ClientCertificateFiles.make(
            certificatePath: fixtures.path(certificate), keyPath: fixtures.path(key), password: nil, in: root)
        #expect(files.keyPassword == nil)
        try expectMatching(files)
    }

    @Test(arguments: ["rsa-encrypted.key", "rsa-encrypted.der", "rsa-legacy-encrypted.key"])
    func encryptedKeysPassThePassword(key: String) throws {
        #expect(ClientCertificate.keyNeedsPassword(atPath: fixtures.path(key)))
        let files = try ClientCertificateFiles.make(
            certificatePath: fixtures.path("rsa.pem"), keyPath: fixtures.path(key),
            password: CertificateFixtures.password, in: root)
        #expect(files.keyPassword == CertificateFixtures.password)
        try expectMatching(files)
    }

    @Test(arguments: ["rsa-encrypted.key", "rsa-encrypted.der"])
    func encryptedKeyWithoutPassword(key: String) {
        #expect(throws: ClientCertificateError.self) {
            try ClientCertificateFiles.make(certificatePath: fixtures.path("rsa.pem"), keyPath: fixtures.path(key), password: nil, in: root)
        }
        do {
            _ = try ClientCertificateFiles.make(certificatePath: fixtures.path("rsa.pem"), keyPath: fixtures.path(key), password: "", in: root)
        } catch {
            #expect(error.kind == .keyNeedsPassword)
        }
    }

    @Test func unencryptedKeysNeedNoPassword() {
        for key in ["rsa.key", "rsa-pkcs8.key", "rsa-pkcs1.der", "rsa-pkcs8.der", "ec-sec1.der"] {
            #expect(!ClientCertificate.keyNeedsPassword(atPath: fixtures.path(key)), "\(key)")
        }
    }

    @Test(arguments: ["rsa.p12", "ec-prime256v1.p12", "ec-secp384r1.p12"])
    func pkcs12Bundles(bundle: String) throws {
        #expect(ClientCertificate.isPKCS12(bundle))
        #expect(ClientCertificate.keyNeedsPassword(atPath: fixtures.path(bundle)))
        let files = try ClientCertificateFiles.make(
            certificatePath: fixtures.path(bundle), keyPath: nil, password: CertificateFixtures.password, in: root)
        #expect(files.keyPassword == nil)
        try expectMatching(files)
        #expect(try permissions(files.keyPath) == 0o600)
    }

    /// Known gap (echo-libraries issue): Security.framework can't open a .p12 that OpenSSL exported
    /// with an empty password. Echo asks for a password and explains how to export it again.
    @Test func pkcs12WithEmptyPasswordIsAKnownGap() {
        #expect(ClientCertificate.keyNeedsPassword(atPath: fixtures.path("rsa-nopass.p12")))
        do {
            _ = try ClientCertificateFiles.make(certificatePath: fixtures.path("rsa-nopass.p12"), keyPath: nil, password: nil, in: root)
            Issue.record("Security.framework opened an empty-password .p12: the gap is closed, update this test and the issue")
        } catch {
            #expect(error.kind == .keyNeedsPassword)
            #expect(error.message.contains("export it again"))
        }
    }

    @Test func pkcs12KeepsTheCAChain() throws {
        let files = try ClientCertificateFiles.make(
            certificatePath: fixtures.path("rsa.p12"), keyPath: nil, password: CertificateFixtures.password, in: root)
        let text = try String(contentsOfFile: files.certificatePath, encoding: .utf8)
        #expect(text.components(separatedBy: "-----BEGIN CERTIFICATE-----").count - 1 == 2)
    }

    @Test func pkcs12PasswordErrors() {
        do {
            _ = try ClientCertificateFiles.make(certificatePath: fixtures.path("rsa.p12"), keyPath: nil, password: "wrong", in: root)
            Issue.record("a wrong password was accepted")
        } catch {
            #expect(error.kind == .wrongKeyPassword)
        }
        do {
            _ = try ClientCertificateFiles.make(certificatePath: fixtures.path("rsa.p12"), keyPath: nil, password: nil, in: root)
            Issue.record("a missing password was accepted")
        } catch {
            #expect(error.kind == .keyNeedsPassword)
        }
    }

    @Test func privatePEMKeyIsUsedWhereItIs() throws {
        let files = try ClientCertificateFiles.make(
            certificatePath: fixtures.path("rsa.pem"), keyPath: fixtures.path("rsa.key"), password: nil, in: root)
        #expect(files.keyPath == fixtures.path("rsa.key"))
        #expect(files.certificatePath == fixtures.path("rsa.pem"))
    }

    @Test func readableKeyIsCopiedToAPrivateFile() throws {
        let shared = fixtures.path("rsa-shared.key")
        try FileManager.default.copyItem(atPath: fixtures.path("rsa.key"), toPath: shared)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: shared)
        let files = try ClientCertificateFiles.make(certificatePath: fixtures.path("rsa.pem"), keyPath: shared, password: nil, in: root)
        #expect(files.keyPath != shared)
        #expect(try permissions(files.keyPath) == 0o600)
        #expect(try permissions(URL(filePath: files.keyPath).deletingLastPathComponent().path) == 0o700)
        #expect(try permissions(shared) == 0o644, "the user's file is never changed")
    }

    @Test func filesAreRemovedWithTheObject() throws {
        var files: ClientCertificateFiles? = try ClientCertificateFiles.make(
            certificatePath: fixtures.path("rsa.p12"), keyPath: nil, password: CertificateFixtures.password, in: root)
        let folder = try #require(files.map { URL(filePath: $0.keyPath).deletingLastPathComponent().path })
        #expect(FileManager.default.fileExists(atPath: folder))
        files = nil
        #expect(!FileManager.default.fileExists(atPath: folder))
    }

    @Test func failedConversionLeavesNothing() throws {
        // The DER certificate is written first; the missing key then fails.
        #expect(throws: ClientCertificateError.self) {
            try ClientCertificateFiles.make(certificatePath: fixtures.path("rsa.der"), keyPath: fixtures.path("missing.key"), password: nil, in: root)
        }
        let left = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        #expect(left.isEmpty)
    }

    @Test func notACertificate() {
        do {
            _ = try ClientCertificateFiles.make(certificatePath: fixtures.path("rsa.key"), keyPath: fixtures.path("rsa.key"), password: nil, in: root)
            Issue.record("a key was accepted as a certificate")
        } catch {
            #expect(error.kind == .certificate)
        }
    }

    @Test func staleFoldersOfDeadProcessesAreRemoved() throws {
        let base = fixtures.directory.appending(path: "tmp")
        let dead = base.appending(path: "Echo-TLS-999999")
        let mine = base.appending(path: "Echo-TLS-\(getpid())")
        try FileManager.default.createDirectory(at: dead, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        ClientCertificateFiles.removeStaleDirectories(in: base)
        #expect(!FileManager.default.fileExists(atPath: dead.path))
        #expect(FileManager.default.fileExists(atPath: mine.path))
    }
}
