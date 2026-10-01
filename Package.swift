// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The release whose zips the binary targets download. scripts/release.sh rewrites these two values.
let release = "1.0.0"
let checksums: [String: String] = [
    "EchoCrypto": "b8f1140b51618a0bfdab21d12b85d2d9a02badf430a7bba45d897641ff15aa6c",
    "EchoLZ4": "58c057f5ffbc562b1c0729f7f8503723b107700ac6e488c1fa0f6d42713c88b2",
    "EchoLibpq": "5eb3c3242ab24fb3c4ba211b5757e0f924a9bffc02dbcb4a6dc410cb3cbcbf0c",
    "EchoMariaDB": "eac22e341bbc900f1d9e6680816a2a50037baa14eab0377aca84f866b1546380",
    "EchoSSL": "5e15f34cd37eb5f98c76bd2a44d53deae46f758dcbeb7ffc12dde321f497bd38",
    "EchoZstd": "b3f30eca238e506304862f83b0ab6226c4eaded40405052e99bfd2226e03bfc2",
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
