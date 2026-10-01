# echo-libraries: agent guide

`CLAUDE.md` is an identical copy of this file; change both together.

## What this repo is
Reproducible universal (arm64 + x86_64) macOS builds of the C libraries and tools Echo ships: OpenSSL, libpq and the PostgreSQL client tools, MariaDB Connector/C, zstd and lz4. They are packaged for Swift Package Manager and consumed by postgres-wire and mysql-wire (branch `official`) and Echo. Part of Echo's driver switch: the plan is `/Users/k/Development/Echo/.planning/OfficialDrivers/` (Phase 1).

## Rules
- **Pin everything.** Versions, URLs and SHA-256 live in `versions.json`; `scripts/fetch.sh` refuses a tarball whose checksum differs. A version bump changes `versions.json` and nothing else, unless the build needs it.
- **No Homebrew, ever.** `scripts/common.sh` resets `PATH`, `PKG_CONFIG` and the compiler variables. CMake builds ignore `/opt/homebrew`, `/usr/local` and `/opt/local`. Never add those paths; `verify.sh` fails on any of them in an install name.
- **Both architectures, deployment target from `versions.json`.** Never build only the host architecture.
- **Patch nothing in upstream sources.** Work around with configure/CMake options or the header shims in `scripts/shims/`, and explain why in the script. MariaDB Connector/C is LGPL: an unmodified build keeps the obligations simple.
- **Security updates first.** A security release of OpenSSL, PostgreSQL or MariaDB Connector/C is bumped, rebuilt and released within 7 days.
- Work on `dev` in small commits; commit messages say what changed for Echo.

## Workflow
`build-all.sh` → `make-frameworks.sh` → `export-headers.sh` + `collect-licenses.sh` (commit their output) → `verify.sh` → `ECHO_LIBRARIES_LOCAL=1 swift test` → `release.sh <x.y.z>` (from `dev`, clean tree; writes checksums into Package.swift, tags, uploads the GitHub Release). CI (`.github/workflows/build.yml`) runs all but the release on every push; `upstream.yml` checks upstream weekly. See `SECURITY-UPDATES.md`.

## Layout
- `scripts/`: `fetch.sh`, one `build-*.sh` per library, `build-all.sh`, `make-frameworks.sh`, `export-headers.sh`, `collect-licenses.sh`, `verify.sh`, `release.sh`, `check-upstream.sh`, `shims/`.
- `Sources/CLibpq`, `Sources/CMariaDB`: the C modules (headers exported from the build, committed). `Tests/`: load tests.
- `Licenses/`: each library's licence (committed).
- `.downloads/`, `.tools/`, `.work/`, `.stage/`, `Artifacts/`: generated, gitignored.
