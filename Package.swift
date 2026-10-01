// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The release whose zips the binary targets download. scripts/release.sh rewrites these two values.
let release = "1.1.0"
let checksums: [String: String] = [
    "EchoCrypto": "679b45a5b51208046a3dc3000f92f02ef5db06fe044058e27054182ad5963ecf",
    "EchoLZ4": "377c423f784c64ceed6650a625b98b10f33fc8b6872215843569d96a7fe98261",
    "EchoLibpq": "b463dbda44b067603bf974b9d33bc0a3e70a4b6e4f3e09753ada03657aa3fed6",
    "EchoMariaDB": "ce7ffbe1ebe029e188788dbcda40704c5928a359cd8a4440042ab19b95491eaa",
    "EchoSSL": "ab287a090de445fd99ab560d12408206246c1726dc18219cf1ae62c0537c51f4",
    "EchoZstd": "7c90468ce78646a651df4717cef2f4b449059b5e52bded764fe9f2ad6d166573",
]

/// `ECHO_LIBRARIES_LOCAL=1` uses the frameworks just built in Artifacts/xcframeworks instead of the
/// release, to try a change before releasing it.
let useLocalBuild = ProcessInfo.processInfo.environment["ECHO_LIBRARIES_LOCAL"] == "1"

func framework(_ name: String) -> Target {
    if useLocalBuild {
        return .binaryTarget(name: name, path: "Artifacts/xcframeworks/\(name).xcframework")
    }
    return .binaryTarget(
        name: name,
        url: "https://github.com/tashda/echo-libraries/releases/download/\(release)/\(name).xcframework.zip",
        checksum: checksums[name] ?? ""
    )
}

let package = Package(
    name: "echo-libraries",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CLibpq", targets: ["CLibpq"]),
        .library(name: "CMariaDB", targets: ["CMariaDB"]),
        .library(name: "EchoTLS", targets: ["EchoTLS"]),
        .library(name: "EchoKerberos", targets: ["EchoKerberos"]),
    ],
    targets: [
        framework("EchoCrypto"),
        framework("EchoSSL"),
        framework("EchoZstd"),
        framework("EchoLZ4"),
        framework("EchoLibpq"),
        framework("EchoMariaDB"),

        // libpq's C API. Also carries zstd and lz4, which libpq itself doesn't need but the bundled
        // pg_dump/pg_restore do: an app that uses CLibpq then embeds everything the tools load.
        .target(
            name: "CLibpq",
            dependencies: ["EchoLibpq", "EchoSSL", "EchoCrypto", "EchoZstd", "EchoLZ4"],
            publicHeadersPath: "include"
        ),
        // MariaDB Connector/C's C API (MySQL and MariaDB).
        .target(
            name: "CMariaDB",
            dependencies: ["EchoMariaDB", "EchoSSL", "EchoCrypto", "EchoZstd"],
            publicHeadersPath: "include"
        ),

        // What OpenSSL doesn't do on a Mac: the Keychain's trusted CAs as a PEM bundle, a macOS
        // check of the server's chain after the handshake, and client certificates in any form the
        // sign-in sheet accepts as the PEM files OpenSSL reads. Swift only; no C is exposed.
        .target(name: "EchoTLS", linkerSettings: [.linkedFramework("Security")]),
        // The user's Kerberos ticket (Apple's GSS.framework), for the sign-in sheet.
        .target(name: "EchoKerberos", linkerSettings: [.linkedFramework("GSS")]),

        .testTarget(name: "EchoLibrariesTests", dependencies: ["CLibpq", "CMariaDB"]),
        .testTarget(name: "EchoTLSTests", dependencies: ["EchoTLS", "EchoKerberos"]),
    ]
)
