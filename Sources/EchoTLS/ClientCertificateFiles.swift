import Foundation
import Security

/// A client certificate and key as PEM files OpenSSL can read (libpq `sslcert`/`sslkey`, MariaDB
/// `MYSQL_OPT_SSL_CERT`/`MYSQL_OPT_SSL_KEY`), made from any form the sign-in sheet accepts: PEM,
/// DER, an encrypted key, or a `.p12`/`.pfx` bundle.
///
/// PEM files the user owns, with a key nobody else can read, are used where they are. Anything
/// else is written to a private folder (0700, files 0600), which is removed when this object goes
/// away; keep it for as long as the connection can reconnect (libpq reads the files each time).
public final class ClientCertificateFiles: Sendable {
    public let certificatePath: String
    public let keyPath: String
    /// The password OpenSSL needs to open the key file (libpq `sslpassword`, MariaDB
    /// `MARIADB_OPT_TLS_PASSPHRASE`); nil when the key file isn't encrypted.
    public let keyPassword: String?
    private let privateDirectory: URL?

    init(certificatePath: String, keyPath: String, keyPassword: String?, privateDirectory: URL?) {
        self.certificatePath = certificatePath
        self.keyPath = keyPath
        self.keyPassword = keyPassword
        self.privateDirectory = privateDirectory
    }

    deinit {
        if let privateDirectory { try? FileManager.default.removeItem(at: privateDirectory) }
    }

    /// This process's folder for converted files: `<tmp>/Echo-TLS-<pid>`.
    public static var processDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "Echo-TLS-\(getpid())", directoryHint: .isDirectory)
    }

    /// - Parameters:
    ///   - certificatePath: a PEM or DER certificate, or a `.p12`/`.pfx` bundle (then `keyPath` is
    ///     not used).
    ///   - keyPath: a PEM or DER private key (PKCS#1, SEC1, PKCS#8, encrypted PKCS#8).
    ///   - password: the key password, or the bundle's.
    public static func make(
        certificatePath: String,
        keyPath: String?,
        password: String?,
        in root: URL = processDirectory
    ) throws(ClientCertificateError) -> ClientCertificateFiles {
        let output = PrivateFolder(root: root)
        do {
            return try make(certificatePath: certificatePath, keyPath: keyPath, password: password, output: output)
        } catch {
            output.remove()
            throw error
        }
    }

    private static func make(
        certificatePath: String,
        keyPath: String?,
        password: String?,
        output: PrivateFolder
    ) throws(ClientCertificateError) -> ClientCertificateFiles {
        let certificateData = try read(certificatePath, what: "client certificate")

        if ClientCertificate.isPKCS12(certificatePath) {
            let contents = try PKCS12Contents.read(certificateData, password: password).get()
            let cert = try output.write(Data(contents.certificatesPEM.utf8), named: "certificate.pem")
            let key = try output.write(Data(contents.keyPEM.utf8), named: "key.pem")
            return ClientCertificateFiles(certificatePath: cert, keyPath: key, keyPassword: nil, privateDirectory: output.directory)
        }

        let cert: String
        if PEM.isPEM(certificateData) {
            guard !PEM.blocks(in: String(decoding: certificateData, as: UTF8.self), label: "CERTIFICATE").isEmpty else {
                throw ClientCertificateError(kind: .certificate, message: "The client certificate at \(certificatePath) is not a certificate. It must be a PEM or DER file, or a .p12/.pfx file.")
            }
            cert = certificatePath
        } else if SecCertificateCreateWithData(nil, certificateData as CFData) != nil {
            cert = try output.write(Data(PEM.encode(certificateData, label: "CERTIFICATE").utf8), named: "certificate.pem")
        } else {
            throw ClientCertificateError(kind: .certificate, message: "The client certificate at \(certificatePath) is not a certificate. It must be a PEM or DER file, or a .p12/.pfx file.")
        }

        guard let keyPath, !keyPath.isEmpty else {
            throw ClientCertificateError(kind: .unreadable, message: "Choose the client key that belongs to the certificate.")
        }
        let keyData = try read(keyPath, what: "client key")
        let encrypted: Bool
        let key: String
        if PEM.isPEM(keyData) {
            let text = String(decoding: keyData, as: UTF8.self)
            guard text.contains("PRIVATE KEY-----") else {
                throw ClientCertificateError(kind: .unreadable, message: "Could not read the client key at \(keyPath): it is not a private key.")
            }
            encrypted = text.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----") || text.contains("Proc-Type: 4,ENCRYPTED")
            key = isPrivateToUser(keyPath) ? keyPath : try output.write(keyData, named: "key.pem")
        } else if let format = PrivateKeyFormat(der: keyData) {
            encrypted = format == .encryptedPKCS8
            key = try output.write(Data(PEM.encode(keyData, label: format.pemLabel).utf8), named: "key.pem")
        } else {
            throw ClientCertificateError(kind: .unreadable, message: "Could not read the client key at \(keyPath): it is not a private key.")
        }
        if encrypted && (password ?? "").isEmpty {
            throw ClientCertificateError(kind: .keyNeedsPassword, message: "The client key at \(keyPath) is protected by a password. Enter the key password.")
        }
        return ClientCertificateFiles(
            certificatePath: cert, keyPath: key,
            keyPassword: encrypted ? password : nil,
            privateDirectory: output.directory
        )
    }

    /// Removes folders left by Echo processes that are no longer running (after a crash).
    public static func removeStaleDirectories(in base: URL = FileManager.default.temporaryDirectory) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: base.path) else { return }
        for name in names where name.hasPrefix("Echo-TLS-") {
            guard let pid = pid_t(name.dropFirst("Echo-TLS-".count)), pid != getpid() else { continue }
            if kill(pid, 0) != 0 && errno == ESRCH {
                try? FileManager.default.removeItem(at: base.appending(path: name))
            }
        }
    }

    private static func read(_ path: String, what: String) throws(ClientCertificateError) -> Data {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ClientCertificateError(kind: .unreadable, message: "Could not open the \(what) at \(path).")
        }
        return data
    }

    /// libpq refuses a key file that others can read, or that someone else owns.
    private static func isPrivateToUser(_ path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let permissions = attributes[.posixPermissions] as? Int,
              let owner = attributes[.ownerAccountID] as? NSNumber else { return false }
        return permissions & 0o077 == 0 && owner.uint32Value == getuid()
    }
}

/// A folder (0700) inside the process folder, made on first write.
final class PrivateFolder {
    let root: URL
    private(set) var directory: URL?

    init(root: URL) { self.root = root }

    func write(_ data: Data, named name: String) throws(ClientCertificateError) -> String {
        do {
            let manager = FileManager.default
            let folder = directory ?? root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            if directory == nil {
                try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                directory = folder
            }
            let file = folder.appending(path: name)
            guard manager.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return file.path
        } catch {
            throw ClientCertificateError(kind: .unreadable, message: "Could not write the client certificate for OpenSSL: \(error.localizedDescription)")
        }
    }

    func remove() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
}
