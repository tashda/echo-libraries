#!/bin/bash
# Wraps each universal framework into an .xcframework (what SwiftPM binary targets take), zips them
# and the PostgreSQL tools for a GitHub Release, and writes their SwiftPM checksums.
#   Artifacts/xcframeworks/<Name>.xcframework
#   Artifacts/release/<Name>.xcframework.zip, PostgresTools.zip, checksums.txt
. "$(dirname "$0")/common.sh"

xc="$ARTIFACTS/xcframeworks"; release="$ARTIFACTS/release"
rm -rf "$xc" "$release" && mkdir -p "$xc" "$release"
: > "$release/checksums.txt"

for fw in "$ARTIFACTS/frameworks"/*.framework; do
  name="$(basename "$fw" .framework)"
  xcodebuild -create-xcframework -framework "$fw" -output "$xc/$name.xcframework" > /dev/null
  (cd "$xc" && ditto -c -k --keepParent "$name.xcframework" "$release/$name.xcframework.zip")
  sum="$(swift package compute-checksum "$release/$name.xcframework.zip")"
  echo "$name $sum" >> "$release/checksums.txt"
  echo "  $name.xcframework.zip $sum"
done

(cd "$ARTIFACTS" && ditto -c -k --keepParent PostgresTools "$release/PostgresTools.zip")
echo "PostgresTools $(shasum -a 256 "$release/PostgresTools.zip" | cut -d' ' -f1)" >> "$release/checksums.txt"
echo "  PostgresTools.zip"
