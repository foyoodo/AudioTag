#!/usr/bin/env bash
# Package AudioTag.app as zip + dmg and verify Mach-O slices with lipo.
#
# Expected environment:
#   APP_PATH     path to AudioTag.app
#   VARIANT      arm64 | universal
#   ARCHS_VALUE  space-separated architectures, e.g. "arm64" or "arm64 x86_64"
#   DERIVED_DATA optional; scanned for TagLib/CTagLib static libraries
set -euo pipefail

APP_PATH="${APP_PATH:?APP_PATH is required}"
VARIANT="${VARIANT:?VARIANT is required}"
ARCHS_VALUE="${ARCHS_VALUE:?ARCHS_VALUE is required}"
DERIVED_DATA="${DERIVED_DATA:-}"

read -r -a EXPECTED_ARCHS <<<"$ARCHS_VALUE"
APP_BIN="$APP_PATH/Contents/MacOS/AudioTag"

if [[ ! -d "$APP_PATH" ]]; then
  echo "::error::Built app not found at $APP_PATH"
  exit 1
fi
if [[ ! -f "$APP_BIN" ]]; then
  echo "::error::App executable not found at $APP_BIN"
  exit 1
fi

is_macho() {
  local file_type
  file_type="$(file -b "$1" 2>/dev/null || true)"
  [[ "$file_type" == Mach-O* ]]
}

verify_binary() {
  local path="$1"
  local info
  if ! is_macho "$path"; then
    return 0
  fi

  echo "lipo -info $path"
  info="$(lipo -info "$path")"
  echo "  $info"

  local arch
  for arch in "${EXPECTED_ARCHS[@]}"; do
    if ! grep -qw -- "$arch" <<<"$info"; then
      echo "::error::$path is missing architecture $arch"
      echo "  $info"
      exit 1
    fi
  done

  if [[ "$VARIANT" == "arm64" ]] && grep -qw x86_64 <<<"$info"; then
    echo "::error::$path unexpectedly contains x86_64 (arm64-only build)"
    echo "  $info"
    exit 1
  fi

  if [[ "$VARIANT" == "universal" ]]; then
    if ! grep -qi "fat file" <<<"$info"; then
      echo "::error::$path is not a fat/universal binary"
      echo "  $info"
      exit 1
    fi
    if ! grep -qw arm64 <<<"$info" || ! grep -qw x86_64 <<<"$info"; then
      echo "::error::$path must contain both arm64 and x86_64"
      echo "  $info"
      exit 1
    fi
  fi
}

echo "=== App executable ==="
file "$APP_BIN"
verify_binary "$APP_BIN"

echo "=== Mach-O files inside the .app ==="
found_bundle_macho=0
while IFS= read -r -d '' macho; do
  found_bundle_macho=1
  verify_binary "$macho"
done < <(find "$APP_PATH" -type f -print0 | while IFS= read -r -d '' candidate; do
  if is_macho "$candidate"; then
    printf '%s\0' "$candidate"
  fi
done)
if [[ "$found_bundle_macho" -eq 0 ]]; then
  echo "::error::No Mach-O files found in $APP_PATH"
  exit 1
fi

if [[ -n "$DERIVED_DATA" && -d "$DERIVED_DATA" ]]; then
  echo "=== TagLib / CTagLib products in DerivedData ==="
  found_taglib=0
  while IFS= read -r -d '' lib; do
    found_taglib=1
    verify_binary "$lib"
  done < <(find "$DERIVED_DATA" \
    \( -iname '*CTagLib*' -o -iname '*TagLib*' \) \
    \( -name '*.a' -o -name '*.dylib' \) \
    -type f -print0)

  if [[ "$found_taglib" -eq 0 ]]; then
    echo "No separate TagLib/CTagLib .a/.dylib products found."
    echo "TagLib is statically linked; the app executable slices are the check."
  fi
fi

mkdir -p dist
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

ZIP_PATH="dist/AudioTag-${VARIANT}.zip"
DMG_PATH="dist/AudioTag-${VARIANT}.dmg"

echo "=== Packaging $ZIP_PATH ==="
ditto -c -k --keepParent --sequesterRsrc "$APP_PATH" "$ZIP_PATH"

echo "=== Packaging $DMG_PATH ==="
rm -f "$DMG_PATH"
hdiutil create \
  -volname "AudioTag" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

ls -lh dist/
echo "Packaged $VARIANT (${ARCHS_VALUE}) successfully."
