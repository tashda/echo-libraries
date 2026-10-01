#!/bin/bash
# libpq and the PostgreSQL client tools (pg_dump, pg_restore, pg_dumpall, psql) for each
# architecture into $STAGE/<arch>/postgresql. Needs build-openssl.sh and build-compression.sh first.
#
# Kerberos uses Apple's GSS.framework (the macOS ticket cache, as Ticket Viewer and `kinit`), not a
# bundled MIT krb5 (decision D4). scripts/shims routes <gssapi/gssapi.h> to <GSS/gssapi.h> (the
# SDK's /usr/include/gssapi is a compatibility layer deprecated since 10.8) and stands in for MIT's
# gssapi_ext.h. PostgreSQL's configure looks for gss_store_cred_into, which only the server uses
# and Apple lacks, so that check is skipped and GSS.framework goes into LDFLAGS (libpq's makefile
# keeps only a fixed list of -l libraries). Client-only build: nothing from src/backend
# is compiled beyond generated headers.
. "$(dirname "$0")/common.sh"

shims="$ROOT/scripts/shims"

for arch in "${ARCHS[@]}"; do
  log "PostgreSQL $(version postgresql) client for $arch"
  src="$(unpack postgresql "$arch")"
  prefix="$STAGE/$arch/postgresql"
  destdir="$WORK/$arch/postgresql-dest"; rm -rf "$destdir"
  ssl="$STAGE/$arch/openssl"; zstd="$STAGE/$arch/zstd"; lz4="$STAGE/$arch/lz4"
  link="-arch $arch -isysroot $SDKROOT -mmacosx-version-min=$DEPLOYMENT_TARGET"
  (
    cd "$src"
    ./configure --prefix="$NEUTRAL_PREFIX/postgresql" \
      --with-ssl=openssl --with-gssapi --with-zstd --with-lz4 --with-zlib \
      --with-libedit-preferred --without-icu --disable-nls \
      --with-includes="$shims:$ssl/include:$zstd/include:$lz4/include" \
      --with-libraries="$ssl/lib:$zstd/lib:$lz4/lib" \
      CC=clang CFLAGS="$(arch_cflags "$arch")" LDFLAGS="$link -framework GSS $LINK_PAD" \
      ZSTD_CFLAGS="-I$zstd/include" ZSTD_LIBS="-L$zstd/lib -lzstd" \
      LZ4_CFLAGS="-I$lz4/include" LZ4_LIBS="-L$lz4/lib -llz4" \
      ac_cv_search_gss_store_cred_into="none required" \
      > "$src/configure.log"
    for dir in src/interfaces/libpq src/bin/pg_dump src/bin/psql; do
      make -C "$dir" -j"$JOBS" >> "$src/build.log"
    done
    for dir in src/include src/interfaces/libpq src/bin/pg_dump src/bin/psql; do
      make -C "$dir" install DESTDIR="$destdir" >> "$src/install.log"
    done
  )
  take_staged postgresql "$arch" "$destdir"
  point_at_stage "$prefix/lib" "$arch"
  for file in lib/libpq.5.dylib bin/pg_dump bin/pg_restore bin/pg_dumpall bin/psql; do
    lipo -archs "$prefix/$file" | grep -qx "$arch" || die "$file is not $arch"
  done
  grep -E "^#define (USE_OPENSSL|ENABLE_GSS|USE_ZSTD|USE_LZ4|HAVE_LIBZ|USE_LIBEDIT_PREFERRED) " "$src/src/include/pg_config.h" | sed 's/^/  /'
done
