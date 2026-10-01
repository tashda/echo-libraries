#!/bin/bash
# zstd and lz4 (shared libraries + headers) for each architecture, used by pg_dump/pg_restore for
# compressed backups. Into $STAGE/<arch>/zstd and $STAGE/<arch>/lz4.
. "$(dirname "$0")/common.sh"

for arch in "${ARCHS[@]}"; do
  # The padding goes in CC: both makefiles build their own LDFLAGS for the dylib, which a
  # command-line LDFLAGS would replace.
  cc="clang $(arch_cflags "$arch") $LINK_PAD"

  log "zstd $(version zstd) for $arch"
  src="$(unpack zstd "$arch")"
  prefix="$STAGE/$arch/zstd"; rm -rf "$prefix"
  make -C "$src/lib" -j"$JOBS" CC="$cc" PREFIX="$prefix" install-shared install-includes > "$src/build.log"
  lipo -archs "$prefix/lib/libzstd.1.dylib" | grep -qx "$arch" || die "libzstd is not $arch"

  log "lz4 $(version lz4) for $arch"
  src="$(unpack lz4 "$arch")"
  prefix="$STAGE/$arch/lz4"; rm -rf "$prefix"
  make -C "$src/lib" -j"$JOBS" CC="$cc" PREFIX="$prefix" BUILD_STATIC=no install > "$src/build.log"
  lipo -archs "$prefix/lib/liblz4.1.dylib" | grep -qx "$arch" || die "liblz4 is not $arch"
done
ls "$STAGE"/*/zstd/lib "$STAGE"/*/lz4/lib
