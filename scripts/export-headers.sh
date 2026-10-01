#!/bin/bash
# Copies the public C headers of libpq and MariaDB Connector/C from the staged build into the Swift
# wrapper targets (Sources/CLibpq/include, Sources/CMariaDB/include). They are committed, so the
# package builds from git. The headers are the same for both architectures; arm64's are used.
. "$(dirname "$0")/common.sh"

pg="$STAGE/arm64/postgresql/include"; my="$STAGE/arm64/mariadb/include/mariadb"
diff -q "$pg/libpq-fe.h" "$STAGE/x86_64/postgresql/include/libpq-fe.h" > /dev/null || die "libpq headers differ by architecture"
diff -rq "$my" "$STAGE/x86_64/mariadb/include/mariadb" > /dev/null || die "MariaDB headers differ by architecture"

dest="$ROOT/Sources/CLibpq/include"
rm -rf "$dest" && mkdir -p "$dest"
cp "$pg/libpq-fe.h" "$pg/libpq-events.h" "$pg/postgres_ext.h" "$dest/"
cat > "$dest/CLibpq.h" <<'EOF'
/* libpq, PostgreSQL's client library (echo-libraries). Only postgres-wire imports this module. */
#include "libpq-fe.h"
#include "libpq-events.h"
EOF

dest="$ROOT/Sources/CMariaDB/include"
rm -rf "$dest" && mkdir -p "$dest"
cp -R "$my"/. "$dest/"
cat > "$dest/CMariaDB.h" <<'EOF'
/* MariaDB Connector/C (echo-libraries), for MySQL and MariaDB. Only mysql-wire imports this module. */
#include "mysql.h"
#include "errmsg.h"
#include "mysqld_error.h"
#include "mariadb_version.h"

/* mysql/client_plugin.h can't be part of the module: the installed copy includes ma_compress.h,
   which Connector/C 3.4.11 doesn't install. mysql.h already declares mysql_client_find_plugin;
   this is the one plugin type Echo asks for. */
#ifndef MYSQL_CLIENT_AUTHENTICATION_PLUGIN
#define MYSQL_CLIENT_AUTHENTICATION_PLUGIN 2
#endif
EOF
# MariaDB keeps headers in subfolders (mysql/, mariadb/), which SwiftPM's generated module map
# doesn't allow next to an umbrella header; this one names the umbrella header explicitly.
cat > "$dest/module.modulemap" <<'EOF'
module CMariaDB {
    header "CMariaDB.h"
    export *
}
EOF
echo "headers exported: $(ls "$ROOT/Sources/CLibpq/include" | wc -l | tr -d ' ') libpq, $(find "$ROOT/Sources/CMariaDB/include" -name '*.h' | wc -l | tr -d ' ') MariaDB"
