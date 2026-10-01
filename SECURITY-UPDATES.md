# Security updates

Echo ships these libraries inside the app, so their security fixes are ours to ship.

- **Watch:** the weekly `Upstream versions` workflow opens an issue when OpenSSL 3.5, PostgreSQL 18, MariaDB Connector/C 3.4, zstd or lz4 publish a newer release. Also follow the [OpenSSL vulnerabilities](https://openssl-library.org/news/vulnerabilities/), [PostgreSQL security](https://www.postgresql.org/support/security/) and MariaDB release notes.
- **Respond:** for a security release, within **7 days**:
  1. bump `versions.json` (URL and SHA-256, checked against the project's published checksum);
  2. `scripts/build-all.sh && scripts/make-frameworks.sh && scripts/export-headers.sh && scripts/collect-licenses.sh && scripts/verify.sh`;
  3. `ECHO_LIBRARIES_LOCAL=1 swift test`;
  4. commit, then `scripts/release.sh <next version>`;
  5. bump Echo's `echo-libraries` pin, build, release Echo through Sparkle.
- Non-security releases go out with the next regular update.
