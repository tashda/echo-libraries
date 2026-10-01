#!/bin/bash
# Downloads every source tarball and build tool in versions.json and checks its SHA-256.
. "$(dirname "$0")/common.sh"

mkdir -p "$DOWNLOADS" "$TOOLS"

fetch() {
  local url="$1" sha="$2" file="$DOWNLOADS/$(basename "$1")"
  if [ ! -f "$file" ] || [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$sha" ]; then
    log "Downloading $(basename "$file")"
    curl -fsSL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" = "$sha" ] || die "checksum mismatch: $file"
  echo "verified $(basename "$file")"
}

for name in $(/usr/bin/python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["libraries"]))' "$ROOT/versions.json"); do
  fetch "$(manifest libraries "$name" url)" "$(manifest libraries "$name" sha256)"
done

cmake_url="$(manifest tools cmake url)"
fetch "$cmake_url" "$(manifest tools cmake sha256)"
if [ ! -d "$TOOLS/$(basename "$cmake_url" .tar.gz)" ]; then
  tar -xf "$DOWNLOADS/$(basename "$cmake_url")" -C "$TOOLS"
fi
echo "cmake ready: $TOOLS/$(basename "$cmake_url" .tar.gz)"
