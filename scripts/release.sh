#!/bin/bash
# Publishes a release: rebuilds the xcframework zips from Artifacts/frameworks, writes their checksums
# and the release number into Package.swift, commits and tags on dev, fast-forwards main, and
# creates the GitHub Release with the zips. Run build-all.sh, make-frameworks.sh and verify.sh first.
#   scripts/release.sh 1.0.0
. "$(dirname "$0")/common.sh"
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"   # for gh only; nothing is built here

release="${1:-}"
[[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release.sh <major.minor.patch>"
cd "$ROOT"
[ "$(git branch --show-current)" = dev ] || die "release from dev"
git diff --quiet && git diff --cached --quiet || die "commit or stash your changes first"
git rev-parse -q --verify "refs/tags/$release" > /dev/null && die "tag $release exists"
command -v gh > /dev/null || die "gh (GitHub CLI) is needed to upload the release"

"$ROOT/scripts/verify.sh"
"$ROOT/scripts/make-xcframeworks.sh"

/usr/bin/python3 - "$release" "$ARTIFACTS/release/checksums.txt" "$ROOT/Package.swift" <<'PY'
import re, sys
release, checksums_path, manifest_path = sys.argv[1:]
sums = {}
for line in open(checksums_path):
    name, value = line.split()
    if name != "PostgresTools":
        sums[name] = value
manifest = open(manifest_path).read()
manifest = re.sub(r'let release = "[^"]*"', f'let release = "{release}"', manifest)
body = "".join(f'    "{name}": "{sums[name]}",\n' for name in sorted(sums))
manifest = re.sub(r'let checksums: \[String: String\] = \[\n.*?\n\]', 'let checksums: [String: String] = [\n' + body + ']', manifest, flags=re.S)
open(manifest_path, "w").write(manifest)
PY

notes="$WORK/release-notes.md"
{
  echo "| Library | Version |"; echo "|---|---|"
  for name in openssl postgresql mariadb-connector-c zstd lz4; do echo "| $name | $(version "$name") |"; done
  echo; echo "Universal (arm64 + x86_64), macOS $DEPLOYMENT_TARGET+. Checksums: \`checksums.txt\`."
} > "$notes"

git add Package.swift
git commit -q -m "Release $release

$(cat "$notes")"
git tag "$release"
git push -q origin dev "$release"
git push -q origin dev:main
gh release create "$release" "$ARTIFACTS"/release/*.zip "$ARTIFACTS/release/checksums.txt" \
  --repo tashda/echo-libraries --title "echo-libraries $release" --notes-file "$notes" --target dev
log "Released $release"
