#!/bin/bash
# Copies each library's licence from its verified source tarball into Licenses/ (committed), for
# Echo's About › Acknowledgements and for the LGPL notice of MariaDB Connector/C.
. "$(dirname "$0")/common.sh"

dest="$ROOT/Licenses"; rm -rf "$dest" && mkdir -p "$dest"
copy() { # <library> <file inside the tarball> <name in Licenses/>
  local name="$1" inner="$2" out="$3" tarball
  tarball="$DOWNLOADS/$(basename "$(manifest libraries "$name" url)")"
  local top; top="$(tar -tf "$tarball" | head -1 | cut -d/ -f1)"
  tar -xOf "$tarball" "$top/$inner" > "$dest/$out" || die "$inner not in $tarball"
}
copy openssl LICENSE.txt "OpenSSL-$(version openssl).txt"
copy postgresql COPYRIGHT "PostgreSQL-$(version postgresql).txt"
copy mariadb-connector-c COPYING.LIB "MariaDB-Connector-C-$(version mariadb-connector-c).txt"
copy zstd LICENSE "zstd-$(version zstd).txt"
copy lz4 lib/LICENSE "lz4-$(version lz4).txt"

cat > "$dest/README.md" <<EOF
# Licences of the libraries Echo ships

| Library | Version | Licence | File |
|---|---|---|---|
| OpenSSL | $(version openssl) | Apache-2.0 | OpenSSL-$(version openssl).txt |
| PostgreSQL (libpq, pg_dump, pg_restore, pg_dumpall, psql) | $(version postgresql) | PostgreSQL | PostgreSQL-$(version postgresql).txt |
| MariaDB Connector/C | $(version mariadb-connector-c) | LGPL-2.1-or-later | MariaDB-Connector-C-$(version mariadb-connector-c).txt |
| zstd | $(version zstd) | BSD-3-Clause | zstd-$(version zstd).txt |
| lz4 (library) | $(version lz4) | BSD-2-Clause | lz4-$(version lz4).txt |

MariaDB Connector/C is used unmodified, as its own dynamic library (EchoMariaDB.framework), which can
be replaced with another build of the same version. Its source is $(manifest libraries mariadb-connector-c url)
(SHA-256 $(manifest libraries mariadb-connector-c sha256)).
EOF
ls "$dest"
