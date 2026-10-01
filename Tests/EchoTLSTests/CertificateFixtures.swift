import Foundation

/// Certificates and keys in every form the sign-in sheet accepts, made with the system's
/// `openssl` (LibreSSL) in a temporary folder.
struct CertificateFixtures {
    static let password = "fixture-pw"
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "EchoTLSTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pw = "pass:\(Self.password)"
        try Self.openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", path("ca.key"), "-out", path("ca.pem"),
                         "-days", "365", "-subj", "/CN=Echo Test CA", "-extensions", "v3_ca", "-config", try caConfig())
        try serverCertificate()
        // RSA client
        try Self.openssl("genrsa", "-out", path("rsa.key"), "2048")
        try sign(key: "rsa.key", name: "rsa", subject: "/CN=echo-rsa")
        try Self.openssl("x509", "-in", path("rsa.pem"), "-outform", "DER", "-out", path("rsa.der"))
        try Self.openssl("rsa", "-in", path("rsa.key"), "-outform", "DER", "-out", path("rsa-pkcs1.der"))
        try Self.openssl("pkcs8", "-topk8", "-nocrypt", "-in", path("rsa.key"), "-out", path("rsa-pkcs8.key"))
        try Self.openssl("pkcs8", "-topk8", "-nocrypt", "-in", path("rsa.key"), "-outform", "DER", "-out", path("rsa-pkcs8.der"))
        try Self.openssl("pkcs8", "-topk8", "-v2", "aes-256-cbc", "-in", path("rsa.key"), "-passout", pw, "-out", path("rsa-encrypted.key"))
        try Self.openssl("pkcs8", "-topk8", "-v2", "aes-256-cbc", "-in", path("rsa.key"), "-passout", pw, "-outform", "DER", "-out", path("rsa-encrypted.der"))
        try Self.openssl("rsa", "-aes256", "-in", path("rsa.key"), "-passout", pw, "-out", path("rsa-legacy-encrypted.key"))
        try Self.openssl("pkcs12", "-export", "-in", path("rsa.pem"), "-inkey", path("rsa.key"), "-certfile", path("ca.pem"),
                         "-passout", pw, "-out", path("rsa.p12"))
        try Self.openssl("pkcs12", "-export", "-in", path("rsa.pem"), "-inkey", path("rsa.key"), "-passout", "pass:", "-out", path("rsa-nopass.p12"))
        // EC client (P-256 and P-384)
        for curve in ["prime256v1", "secp384r1"] {
            try Self.openssl("ecparam", "-name", curve, "-genkey", "-noout", "-out", path("ec-\(curve).key"))
            try sign(key: "ec-\(curve).key", name: "ec-\(curve)", subject: "/CN=echo-ec")
            try Self.openssl("pkcs12", "-export", "-in", path("ec-\(curve).pem"), "-inkey", path("ec-\(curve).key"),
                             "-passout", pw, "-out", path("ec-\(curve).p12"))
        }
        try Self.openssl("ec", "-in", path("ec-prime256v1.key"), "-outform", "DER", "-out", path("ec-sec1.der"))
        for file in try FileManager.default.contentsOfDirectory(atPath: directory.path) where file.hasSuffix(".key") {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path(file))
        }
    }

    func path(_ name: String) -> String { directory.appending(path: name).path }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    /// The public key of a certificate and of a key, as PEM, to show they belong together.
    static func publicKey(certificate: String) throws -> String {
        try openssl("x509", "-in", certificate, "-noout", "-pubkey")
    }

    static func publicKey(key: String, password: String?) throws -> String {
        var arguments = ["pkey", "-in", key, "-pubout"]
        if let password { arguments += ["-passin", "pass:\(password)"] }
        return try openssl(arguments)
    }

    @discardableResult
    static func openssl(_ arguments: String...) throws -> String { try openssl(arguments) }

    @discardableResult
    static func openssl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/openssl")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FixtureError(message: "openssl \(arguments.joined(separator: " ")) failed (\(process.terminationStatus))")
        }
        return String(decoding: data, as: UTF8.self)
    }

    struct FixtureError: Error { let message: String }

    private func sign(key: String, name: String, subject: String) throws {
        try Self.openssl("req", "-new", "-key", path(key), "-subj", subject, "-out", path("\(name).csr"))
        try Self.openssl("x509", "-req", "-in", path("\(name).csr"), "-CA", path("ca.pem"), "-CAkey", path("ca.key"),
                         "-CAcreateserial", "-days", "365", "-out", path("\(name).pem"))
    }

    /// A server certificate for `db.echo.test`, as macOS's TLS policy wants it (SAN, serverAuth).
    private func serverCertificate() throws {
        let extensions = path("server.ext")
        try "subjectAltName=DNS:db.echo.test\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\nbasicConstraints=CA:FALSE\n"
            .write(toFile: extensions, atomically: true, encoding: .utf8)
        try Self.openssl("genrsa", "-out", path("server.key"), "2048")
        try Self.openssl("req", "-new", "-key", path("server.key"), "-subj", "/CN=db.echo.test", "-out", path("server.csr"))
        try Self.openssl("x509", "-req", "-in", path("server.csr"), "-CA", path("ca.pem"), "-CAkey", path("ca.key"),
                         "-CAcreateserial", "-days", "365", "-extfile", extensions, "-out", path("server.pem"))
        try Self.openssl("x509", "-in", path("server.pem"), "-outform", "DER", "-out", path("server.der"))
        try Self.openssl("x509", "-in", path("ca.pem"), "-outform", "DER", "-out", path("ca.der"))
    }

    private func caConfig() throws -> String {
        let config = path("ca.cnf")
        try """
        [req]
        distinguished_name = dn
        [dn]
        [v3_ca]
        basicConstraints = critical,CA:TRUE
        keyUsage = critical,keyCertSign,cRLSign
        subjectKeyIdentifier = hash
        """.write(toFile: config, atomically: true, encoding: .utf8)
        return config
    }
}
