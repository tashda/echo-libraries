#!/bin/bash
# Turns the staged per-architecture libraries into universal macOS frameworks, and the PostgreSQL
# tools into universal executables, all finding each other through @rpath:
#   Artifacts/frameworks/<Name>.framework   install name @rpath/<Name>.framework/Versions/A/<Name>
#   Artifacts/PostgresTools/<tool>          rpath @executable_path/../../Frameworks, for
#                                           Echo.app/Contents/SharedSupport/PostgresTools/<tool>
# Everything is signed ad hoc here; Xcode re-signs with Echo's team when it embeds them.
. "$(dirname "$0")/common.sh"

# framework name | staged dylib (relative to $STAGE/<arch>) | version source
FRAMEWORKS=(
  "EchoCrypto|openssl/lib/libcrypto.3.dylib|openssl"
  "EchoSSL|openssl/lib/libssl.3.dylib|openssl"
  "EchoZstd|zstd/lib/libzstd.1.dylib|zstd"
  "EchoLZ4|lz4/lib/liblz4.1.dylib|lz4"
  "EchoLibpq|postgresql/lib/libpq.5.dylib|postgresql"
  "EchoMariaDB|mariadb/lib/mariadb/libmariadb.3.dylib|mariadb-connector-c"
)
TOOLS_LIST=(pg_dump pg_restore pg_dumpall psql)

# The framework that replaces a dependency, by the dependency's file name.
framework_for() {
  case "$(basename "$1")" in
    libcrypto.3.dylib) echo EchoCrypto ;;
    libssl.3.dylib) echo EchoSSL ;;
    libzstd.1.dylib) echo EchoZstd ;;
    liblz4.1.dylib) echo EchoLZ4 ;;
    libpq.5.dylib) echo EchoLibpq ;;
    libmariadb.3.dylib) echo EchoMariaDB ;;
    *) echo "" ;;
  esac
}
rpath_of() { echo "@rpath/$1.framework/Versions/A/$1"; }

# Rewrites every non-system dependency of a Mach-O file to its framework; fails on anything else.
relink() {
  local file="$1" dep target
  for dep in $(otool -L "$file" | tail -n +2 | awk '{print $1}'); do
    case "$dep" in /usr/lib/*|/System/*|@rpath/*.framework/*) continue ;; esac
    target="$(framework_for "$dep")"
    [ -n "$target" ] || die "$file depends on $dep, which is not one of our frameworks"
    install_name_tool -change "$dep" "$(rpath_of "$target")" "$file" 2>/dev/null
  done
  # Drop any rpath that points into the build machine.
  for dep in $(otool -l "$file" | awk '/LC_RPATH/{getline; getline; print $2}'); do
    case "$dep" in @*) ;; *) install_name_tool -delete_rpath "$dep" "$file" 2>/dev/null ;; esac
  done
}

info_plist() {
  local name="$1" version="$2"
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>dev.echodb.libraries.$name</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>LSMinimumSystemVersion</key><string>$DEPLOYMENT_TARGET</string>
</dict>
</plist>
EOF
}

out="$ARTIFACTS/frameworks"; tmp="$WORK/frameworks"
rm -rf "$out" "$tmp" && mkdir -p "$out" "$tmp"

for entry in "${FRAMEWORKS[@]}"; do
  IFS='|' read -r name rel source <<< "$entry"
  log "$name.framework"
  slices=()
  for arch in "${ARCHS[@]}"; do
    slice="$tmp/$arch/$name"; mkdir -p "$tmp/$arch"
    cp "$STAGE/$arch/$rel" "$slice"
    install_name_tool -id "$(rpath_of "$name")" "$slice" 2>/dev/null
    relink "$slice"
    slices+=("$slice")
  done
  fw="$out/$name.framework"
  mkdir -p "$fw/Versions/A/Resources"
  lipo -create "${slices[@]}" -output "$fw/Versions/A/$name"
  info_plist "$name" "$(version "$source")" > "$fw/Versions/A/Resources/Info.plist"
  ln -s A "$fw/Versions/Current"
  ln -s "Versions/Current/$name" "$fw/$name"
  ln -s Versions/Current/Resources "$fw/Resources"
  codesign -f -s - "$fw" 2>/dev/null
  echo "  $(lipo -archs "$fw/$name") | $(otool -L "$fw/$name" | tail -n +3 | awk '{print $1}' | tr '\n' ' ')"
done

log "PostgreSQL tools"
tools_out="$ARTIFACTS/PostgresTools"; rm -rf "$tools_out" && mkdir -p "$tools_out"
for tool in "${TOOLS_LIST[@]}"; do
  slices=()
  for arch in "${ARCHS[@]}"; do
    slice="$tmp/$arch/$tool"
    cp "$STAGE/$arch/postgresql/bin/$tool" "$slice"
    relink "$slice"
    install_name_tool -add_rpath "@executable_path/../../Frameworks" "$slice" 2>/dev/null
    slices+=("$slice")
  done
  lipo -create "${slices[@]}" -output "$tools_out/$tool"
  codesign -f -s - "$tools_out/$tool" 2>/dev/null
  echo "  $tool: $(lipo -archs "$tools_out/$tool") | $(otool -L "$tools_out/$tool" | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
done
echo "$(version postgresql)" > "$tools_out/VERSION"
