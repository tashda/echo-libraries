#!/bin/bash
# Shared settings for every build script. Source it: `. "$(dirname "$0")/common.sh"`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOADS="$ROOT/.downloads"        # verified source tarballs
TOOLS="$ROOT/.tools"                # build tools we fetch ourselves (CMake)
WORK="$ROOT/.work"                  # unpacked sources and per-architecture builds
STAGE="$ROOT/.stage"                # per-architecture install prefixes: $STAGE/<arch>/<library>
ARTIFACTS="$ROOT/Artifacts"         # universal frameworks, xcframeworks, tools

# A clean PATH: Xcode and the system only, so nothing from Homebrew or MacPorts can leak into a
# build (pkg-config, OpenSSL, krb5, gettext, …). Our own CMake is added by `use_cmake`.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
unset PKG_CONFIG_PATH PKG_CONFIG CPATH LIBRARY_PATH C_INCLUDE_PATH DYLD_LIBRARY_PATH LDFLAGS CPPFLAGS CFLAGS || true
export PKG_CONFIG=/usr/bin/false

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
DEPLOYMENT_TARGET="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["deploymentTarget"])' "$ROOT/versions.json")"
export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
ARCHS=(arm64 x86_64)
JOBS="$(sysctl -n hw.ncpu)"

# version <library>, url <library>, sha <library>
manifest() { /usr/bin/python3 - "$ROOT/versions.json" "$@" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
kind, name, field = sys.argv[2], sys.argv[3], sys.argv[4]
print(data[kind][name][field])
PY
}
version() { manifest libraries "$1" version; }

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Host triplet for autoconf, per architecture.
autoconf_host() { case "$1" in arm64) echo aarch64-apple-darwin ;; x86_64) echo x86_64-apple-darwin ;; esac; }

# Compiler flags for one architecture, deployment target and SDK.
arch_cflags() { echo "-arch $1 -isysroot $SDKROOT -mmacosx-version-min=$DEPLOYMENT_TARGET -O2"; }

use_cmake() {
  local version; version="$(manifest tools cmake version)"
  local bin="$TOOLS/cmake-$version-macos-universal/CMake.app/Contents/bin"
  [ -x "$bin/cmake" ] || die "CMake $version missing: run scripts/fetch.sh"
  export PATH="$bin:$PATH"
}

# Unpack a verified tarball into $WORK/<arch>/<name>-<version>; prints the directory.
unpack() {
  local name="$1" arch="$2" version file dir
  version="$(version "$name")"
  file="$DOWNLOADS/$(basename "$(manifest libraries "$name" url)")"
  [ -f "$file" ] || die "$file missing: run scripts/fetch.sh"
  dir="$WORK/$arch/$name"
  rm -rf "$dir" && mkdir -p "$dir"
  tar -xf "$file" -C "$dir" --strip-components 1
  echo "$dir"
}
