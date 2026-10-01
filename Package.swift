// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The release whose zips the binary targets download. scripts/release.sh rewrites these two values.
let release = "1.0.0"
let checksums: [String: String] = [
    "EchoCrypto": "2d142837726647073bd64546081ed2c617ab064c212b71efa1e1398634bc4f53",
    "EchoLZ4": "5388840524513f8a4559744d6fa48b1f97baa9226d5ed1e945ccf550589f4cfa",
    "EchoLibpq": "641b11cd687fed7dde45640f60ed4668332321e57fedd2cd72fa23027fd3b8f0",
    "EchoMariaDB": "72a857d01be0bf32c7b529b6376f6bc81d35d7c819fa85b57e03f832b95c4ddc",
    "EchoSSL": "0c048618a47b3e927bdacfcb1671806864f349022cee3de5d3217e2834a9ffb2",
    "EchoZstd": "c459f01f8dbc7bd6c86652731620259919d9e5f3c780771787f4a844fbad3c95",
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

        .testTarget(name: "EchoLibrariesTests", dependencies: ["CLibpq", "CMariaDB"]),
    ]
)
