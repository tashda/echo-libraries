#!/bin/bash
# Compares versions.json with the newest upstream releases on the same line (OpenSSL 3.5 LTS,
# PostgreSQL 18, MariaDB Connector/C 3.4, zstd 1.5, lz4 1.x). Prints what is newer; exits 1 if
# anything is, so CI can open an issue. Security releases must be shipped within 7 days.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
current() { /usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["libraries"][sys.argv[2]]["version"])' "$ROOT/versions.json" "$1"; }
latest_tag() { # <repo> <regex with one group for the version>
  curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "https://api.github.com/repos/$1/tags?per_page=100" |
    /usr/bin/python3 -c 'import json,re,sys
pat=re.compile(sys.argv[1]); vs=[]
for t in json.load(sys.stdin):
    m=pat.fullmatch(t["name"])
    if m: vs.append(tuple(int(x) for x in m.group(1).split(".")))
print(".".join(map(str,max(vs))) if vs else "")' "$2"
}
newest_postgres() {
  curl -fsSL https://ftp.postgresql.org/pub/source/ | grep -oE 'v18\.[0-9]+/' | tr -d 'v/' | sort -t. -k2 -n | tail -1
}

outdated=0
check() { # <name> <current> <latest>
  if [ -n "$3" ] && [ "$3" != "$2" ] && [ "$(printf '%s\n%s\n' "$2" "$3" | sort -V | tail -1)" = "$3" ]; then
    echo "$1: $2 -> $3"; outdated=1
  else
    echo "$1: $2 (current)"
  fi
}
check openssl "$(current openssl)" "$(latest_tag openssl/openssl 'openssl-(3\.5\.[0-9]+)')"
check postgresql "$(current postgresql)" "$(newest_postgres)"
check mariadb-connector-c "$(current mariadb-connector-c)" "$(latest_tag mariadb-corporation/mariadb-connector-c 'v(3\.4\.[0-9]+)')"
check zstd "$(current zstd)" "$(latest_tag facebook/zstd 'v(1\.5\.[0-9]+)')"
check lz4 "$(current lz4)" "$(latest_tag lz4/lz4 'v(1\.[0-9]+\.[0-9]+)')"
exit $outdated
