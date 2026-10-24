#!/usr/bin/env bash
# Ad-hoc sign AudioTag.app with sandbox entitlements, verify architectures
# with lipo, then zip + dmg using versioned file names.
#
# Expected environment:
#   APP_PATH     path to AudioTag.app
#   VARIANT      arm64 | universal
#   ARCHS_VALUE  space-separated architectures, e.g. "arm64" or "arm64 x86_64"
#   DERIVED_DATA optional; scanned for TagLib/CTagLib static libraries
#   GITHUB_REF / GITHUB_REF_NAME / GITHUB_SHA  from Actions
#   GITHUB_OUTPUT optional; writes asset_stem for upload-artifact
set -euo pipefail

APP_PATH="${APP_PATH:?APP_PATH is required}"
VARIANT="${VARIANT:?VARIANT is required}"
ARCHS_VALUE="${ARCHS_VALUE:?ARCHS_VALUE is required}"
DERIVED_DATA="${DERIVED_DATA:-}"

read -r -a EXPECTED_ARCHS <<<"$ARCHS_VALUE"
APP_BIN="$APP_PATH/Contents/MacOS/AudioTag"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

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

find_entitlements() {
  local settings entitlements srcroot
  settings="$(
    xcodebuild -showBuildSettings \
      -workspace AudioTag.xcworkspace \
      -scheme AudioTag \
      -configuration Release \
      -destination generic/platform=macOS \
      ${DERIVED_DATA:+-derivedDataPath "$DERIVED_DATA"} \
      2>/dev/null || true
  )"
  entitlements="$(sed -n 's/^[[:space:]]*CODE_SIGN_ENTITLEMENTS = //p' <<<"$settings" | tail -1)"
  srcroot="$(sed -n 's/^[[:space:]]*SRCROOT = //p' <<<"$settings" | tail -1)"
  if [[ -n "$entitlements" ]]; then
    if [[ "$entitlements" != /* && -n "$srcroot" ]]; then
      entitlements="$srcroot/$entitlements"
    fi
    if [[ -f "$entitlements" ]]; then
      printf '%s\n' "$entitlements"
      return 0
    fi
  fi
  # Tuist writes dictionary entitlements under Derived/.
  find . Derived "${DERIVED_DATA:-/nonexistent}" \
    -name '*.entitlements' \
    -type f \
    2>/dev/null | head -1
}

echo "=== App executable ==="
file "$APP_BIN"
verify_binary "$APP_BIN"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
echo "CFBundleShortVersionString=$APP_VERSION"
echo "CFBundleVersion=$APP_BUILD"

if [[ -z "$APP_VERSION" ]]; then
  echo "::error::CFBundleShortVersionString missing from $INFO_PLIST"
  exit 1
fi

if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  TAG_VERSION="${GITHUB_REF_NAME#v}"
  if [[ "$TAG_VERSION" != "$APP_VERSION" ]]; then
    echo "::error::Git tag v${TAG_VERSION} does not match project version ${APP_VERSION} (CFBundleShortVersionString). Bump MARKETING_VERSION in Project.swift or retag."
    exit 1
  fi
  ASSET_VERSION="$APP_VERSION"
else
  SHORT_SHA="$(git rev-parse --short=7 HEAD 2>/dev/null || echo "${GITHUB_SHA:0:7}")"
  ASSET_VERSION="${APP_VERSION}-${SHORT_SHA}"
fi
ASSET_STEM="AudioTag-${ASSET_VERSION}-${VARIANT}"
echo "ASSET_STEM=$ASSET_STEM"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "asset_stem=$ASSET_STEM" >> "$GITHUB_OUTPUT"
fi

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

ENTITLEMENTS="$(find_entitlements || true)"
if [[ -z "$ENTITLEMENTS" || ! -f "$ENTITLEMENTS" ]]; then
  echo "::error::Could not find the entitlements file Tuist generated (CODE_SIGN_ENTITLEMENTS)."
  exit 1
fi
echo "Entitlements file: $ENTITLEMENTS"
plutil -p "$ENTITLEMENTS" || cat "$ENTITLEMENTS"

echo "=== Ad-hoc sign (nested code without entitlements, bundle with entitlements) ==="
while IFS= read -r nested; do
  [[ -z "$nested" ]] && continue
  [[ "$nested" == "$APP_BIN" ]] && continue
  echo "codesign --force --sign - $nested"
  codesign --force --sign - --timestamp=none "$nested"
done < <(
  find "$APP_PATH" -type f -print0 \
    | while IFS= read -r -d '' candidate; do
        if is_macho "$candidate"; then
          printf '%s\n' "$candidate"
        fi
      done \
    | awk -F/ '{ print NF, $0 }' \
    | sort -nr \
    | awk '{ $1=""; sub(/^ /,""); print }'
)

echo "codesign --force --sign - --entitlements $ENTITLEMENTS $APP_PATH"
codesign --force --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$APP_PATH"

echo "=== codesign --verify --deep --strict ==="
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true

echo "=== codesign -d --entitlements - ==="
ENTITLEMENTS_DUMP="$(mktemp)"
# XML on stdout (`:-`); fall back to writing a plist file.
if ! codesign -d --entitlements :- "$APP_PATH" >"$ENTITLEMENTS_DUMP" 2>/dev/null; then
  codesign -d --entitlements - "$APP_PATH" >"$ENTITLEMENTS_DUMP" 2>/dev/null \
    || codesign -d --entitlements "$ENTITLEMENTS_DUMP" "$APP_PATH"
fi
cat "$ENTITLEMENTS_DUMP"
python3 - "$ENTITLEMENTS_DUMP" <<'PY'
import pathlib, plistlib, re, sys

raw = pathlib.Path(sys.argv[1]).read_bytes()
for marker in (b"<?xml", b"<plist", b"bplist"):
    idx = raw.find(marker)
    if idx != -1:
        raw = raw[idx:]
        break
try:
    data = plistlib.loads(raw)
except Exception:
    text = raw.decode("utf-8", "replace")
    if "com.apple.security.app-sandbox" in text and re.search(
        r"app-sandbox(?:</key>)?\s*(?:<true\s*/>|true|\[Bool\] true)", text, re.I | re.S
    ):
        sys.exit(0)
    raise SystemExit("could not parse entitlements dump") from None

value = data.get("com.apple.security.app-sandbox")
print("com.apple.security.app-sandbox =", value)
if value is not True:
    raise SystemExit("com.apple.security.app-sandbox is not true")
PY
echo "Sandbox entitlement com.apple.security.app-sandbox is present and true."

mkdir -p dist
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING" "$ENTITLEMENTS_DUMP"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

ZIP_PATH="dist/${ASSET_STEM}.zip"
DMG_PATH="dist/${ASSET_STEM}.dmg"

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
echo "Packaged $ASSET_STEM (${ARCHS_VALUE}) successfully."
