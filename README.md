# echo-libraries

Reproducible builds of the C libraries and command-line tools that [Echo](https://github.com/tashda/Echo) ships, for macOS on Apple silicon and Intel:

| Library | Version | Licence | Used for |
|---|---|---|---|
| OpenSSL | 3.5.9 (LTS) | Apache-2.0 | TLS for libpq and MariaDB Connector/C |
| libpq + `pg_dump`, `pg_restore`, `pg_dumpall`, `psql` | PostgreSQL 18.6 | PostgreSQL | Echo's PostgreSQL connections, backups and console |
| MariaDB Connector/C | 3.4.11 | LGPL-2.1-or-later | Echo's MySQL and MariaDB connections |
| zstd | 1.5.7 | BSD-3-Clause | Compressed backups (`pg_dump`), MySQL compression |
| lz4 | 1.10.0 | BSD-2-Clause | Compressed backups (`pg_dump`) |

Every version and source checksum is pinned in [`versions.json`](versions.json). Builds use only Xcode, the macOS SDK and a pinned CMake that the scripts download themselves; nothing from Homebrew or MacPorts is used, even when installed.

## Building

```bash
scripts/build-all.sh
```

That downloads and verifies the sources (`.downloads/`) and CMake (`.tools/`), then builds each library for arm64 and x86_64 into `.stage/<arch>/<library>/`. Then:

```bash
scripts/make-frameworks.sh   # universal frameworks + PostgreSQL tools in Artifacts/
scripts/export-headers.sh    # C headers into Sources/CLibpq and Sources/CMariaDB
scripts/verify.sh            # architectures, dependencies, compiled-in paths, smoke test
ECHO_LIBRARIES_LOCAL=1 swift test
scripts/release.sh 1.2.3     # zips, checksums into Package.swift, tag, GitHub Release
```

## Using it

```swift
.package(url: "https://github.com/tashda/echo-libraries", from: "1.0.0"),
// …
.product(name: "CLibpq", package: "echo-libraries")     // libpq (postgres-wire)
.product(name: "CMariaDB", package: "echo-libraries")   // MariaDB Connector/C (mysql-wire)
.product(name: "EchoTLS", package: "echo-libraries")    // Keychain trust, client certificates
.product(name: "EchoKerberos", package: "echo-libraries") // the user's Kerberos ticket
```

### What OpenSSL doesn't do on a Mac (`EchoTLS`, `EchoKerberos`)
libpq and MariaDB Connector/C use OpenSSL, which doesn't read the Keychain. Two Swift modules (no C exposed) cover the difference:
- **`TrustBundle`** writes the CAs this Mac trusts for TLS servers to a PEM file for `sslrootcert` / `MYSQL_OPT_SSL_CA`: the system roots plus admin and user trust settings (company CAs from IT or MDM), minus anything marked "Never Trust". Trust limited to one host or one app is left out.
- **`ServerTrust`** has macOS evaluate the server's chain again after the handshake, so "Never Trust" and the rest of macOS's TLS policy still apply.
- **`ClientCertificateFiles`** turns any client certificate the sign-in sheet accepts (PEM, DER, PKCS#1/SEC1/PKCS#8, encrypted keys, `.p12`/`.pfx` including legacy 3DES/RC2 ones) into PEM files OpenSSL reads, in a private folder (0700, files 0600) that goes away with the object. Known gap: a `.p12` exported with an *empty* password can't be opened (Security.framework and OpenSSL compute its MAC differently).
- **`KerberosTicket.current()`** (`EchoKerberos`) reads the ticket from Apple's GSS.framework, the same cache libpq and Connector/C sign in with.

The binary frameworks (`EchoLibpq`, `EchoMariaDB`, `EchoSSL`, `EchoCrypto`, `EchoZstd`, `EchoLZ4`) come from the GitHub Release named in `Package.swift`, checked against their checksums; Xcode embeds and signs them in the app. The PostgreSQL tools are the release's `PostgresTools.zip`: Echo copies them to `Contents/SharedSupport/PostgresTools/`, where they find the frameworks in `Contents/Frameworks/`.

### Choices worth knowing
- **Kerberos uses Apple's GSS.framework** (the system ticket cache that Ticket Viewer and `kinit` use), not a bundled MIT Kerberos. `scripts/shims/gssapi/` routes the GSS-API headers to GSS.framework and stands in for MIT's `gssapi_ext.h`, which only the PostgreSQL server needs.
- **PostgreSQL is built client-only**: libpq and the client tools, no server.
- **MariaDB Connector/C has every plugin built in**: sign-in (native, caching_sha2, sha256, ed25519, parsec, dialog/PAM, cleartext, GSSAPI) and compression (zlib, zstd). Nothing is loaded from a plugin directory at run time.
- **macOS 26 deployment target.**

## Licences
Each library keeps its own licence (table above). MariaDB Connector/C is LGPL-2.1: it is shipped unmodified, as its own dynamic library that can be replaced, and its source is the tarball pinned in `versions.json`.
