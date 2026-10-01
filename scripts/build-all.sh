#!/bin/bash
# Fetches and builds everything, in dependency order.
set -euo pipefail
cd "$(dirname "$0")"
./fetch.sh
./build-openssl.sh
./build-compression.sh
./build-libpq.sh
./build-mariadb.sh
