#!/bin/bash
# Checks the packaged artifacts the way Echo will use them:
#  1. every binary has both architectures and no dependency outside our frameworks and the system;
#  2. no build-machine or Homebrew path is compiled in;
#  3. inside an app-shaped folder (Contents/Frameworks + Contents/SharedSupport/PostgresTools), every
#     tool runs, and a small C program loads libpq and MariaDB Connector/C and calls into them,
#     natively and as x86_64 (Rosetta).
. "$(dirname "$0")/common.sh"

frameworks="$ARTIFACTS/frameworks"; tools="$ARTIFACTS/PostgresTools"
failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

log "Architectures, dependencies, compiled-in paths"
binaries=()
for fw in "$frameworks"/*.framework; do binaries+=("$fw/$(basename "$fw" .framework)"); done
for tool in "$tools"/*; do [ -x "$tool" ] && binaries+=("$tool"); done
for bin in "${binaries[@]}"; do
  archs="$(lipo -archs "$bin")"
  [ "$archs" = "x86_64 arm64" ] || fail "$bin is '$archs'"
  # Universal files: otool prints a "<file> (architecture x):" header per slice; skip those.
  for dep in $(otool -L "$bin" | grep -v ':$' | awk '{print $1}' | sort -u); do
    case "$dep" in /usr/lib/*|/System/Library/*|@rpath/Echo*.framework/Versions/A/Echo*) ;; *) fail "$bin depends on $dep" ;; esac
  done
  ids="$(otool -L "$bin" | grep -v ':$' | awk '{print $1}')"
  if strings -a "$bin" | grep -E "/Users/|/opt/homebrew|/usr/local/(opt|Cellar)" | grep -qvxF "$ids"; then
    fail "$bin contains a build-machine or Homebrew path"
  fi
  codesign --verify "$bin" 2>/dev/null || fail "$bin signature"
done
echo "  checked ${#binaries[@]} binaries"

log "Smoke test in an app-shaped folder"
app="$WORK/Smoke.app/Contents"; rm -rf "$WORK/Smoke.app"
mkdir -p "$app/Frameworks" "$app/SharedSupport/PostgresTools" "$app/MacOS"
cp -R "$frameworks"/*.framework "$app/Frameworks/"
cp "$tools"/* "$app/SharedSupport/PostgresTools/"

cat > "$WORK/smoke.c" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <libpq-fe.h>
#include <mysql.h>
int main(void) {
    int pq = PQlibVersion();
    /* Port 9 on localhost: nothing listens, so this fails fast and proves the library works. */
    PGconn *conn = PQconnectdb("host=127.0.0.1 port=9 connect_timeout=2 gssencmode=disable");
    int pqFailed = PQstatus(conn) == CONNECTION_BAD;
    PQfinish(conn);
    unsigned long my = mysql_get_client_version();
    MYSQL *m = mysql_init(NULL);
    int myFailed = mysql_real_connect(m, "127.0.0.1", "u", "p", NULL, 9, NULL, 0) == NULL;
    mysql_close(m);
    printf("libpq %d (refused: %d), mariadb %lu (refused: %d), ssl: %s\n", pq, pqFailed, my, myFailed,
           PQsslAttribute(NULL, "library") ? PQsslAttribute(NULL, "library") : "none");
    return (pq >= 180000 && pqFailed && my >= 30400 && myFailed) ? 0 : 1;
}
EOF
for arch in "${ARCHS[@]}"; do
  clang $(arch_cflags "$arch") \
    -I "$STAGE/$arch/postgresql/include" -I "$STAGE/$arch/mariadb/include/mariadb" \
    -F "$frameworks" -framework EchoLibpq -framework EchoMariaDB \
    -Wl,-rpath,@executable_path/../Frameworks -o "$app/MacOS/smoke-$arch" "$WORK/smoke.c"
  codesign -f -s - "$app/MacOS/smoke-$arch" 2>/dev/null
  run=(); [ "$arch" = x86_64 ] && run=(arch -x86_64)
  ${run[@]+"${run[@]}"} "$app/MacOS/smoke-$arch" | sed "s/^/  $arch: /" || fail "smoke program ($arch)"
  for tool in pg_dump pg_restore pg_dumpall psql; do
    out="$(${run[@]+"${run[@]}"} "$app/SharedSupport/PostgresTools/$tool" --version 2>&1)" || fail "$tool ($arch): $out"
    echo "  $arch: $out"
  done
done

[ "$failures" = 0 ] && log "All checks passed" || die "$failures check(s) failed"
