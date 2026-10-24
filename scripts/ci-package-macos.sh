#!/usr/bin/env bash
# Ad-hoc sign AudioTag.app with sandbox entitlements, verify architectures
# with lipo, then zip + dmg using versioned file names.
#
# Sparkle.framework is signed inside-out (XPC services, Autoupdate, Updater.app,
# then the framework) without --deep, preserving helper entitlements. The app
# bundle is signed last with the Tuist-generated sandbox entitlements.
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

# Ad-hoc sign a Sparkle helper, keeping identifier / entitlements / hardened
# runtime flags from the copy that shipped inside the XCFramework.
codesign_sparkle_helper() {
  local target="$1"
  echo "codesign --force --sign - --preserve-metadata $target"
  if ! codesign --force --sign - --timestamp=none \
    --preserve-metadata=identifier,entitlements,flags,runtime "$target"; then
    codesign --force --sign - --timestamp=none \
      --preserve-metadata=identifier,flags,runtime "$target"
  fi
}

# Sparkle's XCFramework ships a universal macOS slice. The arm64-only package
# must not contain x86_64, so extra architectures are stripped before signing.
thin_to_expected_archs() {
  local path="$1"
  local info tmp mode
  if ! is_macho "$path"; then
    return 0
  fi
  info="$(lipo -info "$path")"
  if [[ "$VARIANT" != "arm64" ]] || ! grep -qw x86_64 <<<"$info"; then
    return 0
  fi
  echo "lipo -thin arm64 $path"
  tmp="$(mktemp)"
  lipo "$path" -thin arm64 -output "$tmp"
  if mode="$(stat -f %Lp "$path" 2>/dev/null)"; then
    chmod "$mode" "$tmp"
  elif [[ -x "$path" ]]; then
    chmod +x "$tmp"
  fi
  mv "$tmp" "$path"
}

# Unique real paths under Sparkle.framework (find does not follow dir symlinks,
# so Versions/Current duplicates are skipped).
sparkle_paths() {
  local fw="$1"
  local name="$2"
  find "$fw" -name "$name" \( -type d -o -type f \) -print \
    | while IFS= read -r path; do
        python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path"
      done \
    | awk 'NF && !seen[$0]++'
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

echo "=== Thin extra architectures ==="
while IFS= read -r -d '' macho; do
  thin_to_expected_archs "$macho"
done < <(find "$APP_PATH" -type f -print0 | while IFS= read -r -d '' candidate; do
  if is_macho "$candidate"; then
    printf '%s\0' "$candidate"
  fi
done)

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
  # Sparkle helpers are bundles that must keep their own entitlements; signing
  # their inner Mach-O files here would strip them. Handled below.
  [[ "$nested" == *"/Sparkle.framework/"* ]] && continue
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

SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE_FW" ]]; then
  echo "::error::Sparkle.framework is missing from $APP_PATH/Contents/Frameworks"
  exit 1
fi

echo "=== Ad-hoc sign Sparkle helpers (inside-out, no --deep) ==="
while IFS= read -r xpc; do
  [[ -z "$xpc" ]] && continue
  codesign_sparkle_helper "$xpc"
done < <(sparkle_paths "$SPARKLE_FW" "*.xpc")

while IFS= read -r helper; do
  [[ -z "$helper" ]] && continue
  codesign_sparkle_helper "$helper"
done < <(sparkle_paths "$SPARKLE_FW" "Autoupdate")

while IFS= read -r updater; do
  [[ -z "$updater" ]] && continue
  codesign_sparkle_helper "$updater"
done < <(sparkle_paths "$SPARKLE_FW" "Updater.app")

codesign_sparkle_helper "$SPARKLE_FW"

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
    if (
        "com.apple.security.app-sandbox" in text
        and re.search(
            r"app-sandbox(?:</key>)?\s*(?:<true\s*/>|true|\[Bool\] true)", text, re.I | re.S
        )
        and "com.foyoodo.AudioTag-spks" in text
        and "com.foyoodo.AudioTag-spki" in text
    ):
        sys.exit(0)
    raise SystemExit("could not parse entitlements dump") from None

value = data.get("com.apple.security.app-sandbox")
print("com.apple.security.app-sandbox =", value)
if value is not True:
    raise SystemExit("com.apple.security.app-sandbox is not true")

lookup = data.get("com.apple.security.temporary-exception.mach-lookup.global-name")
print("mach-lookup.global-name =", lookup)
if not isinstance(lookup, list):
    raise SystemExit("Sparkle mach-lookup exception is missing")
needed = {
    "com.foyoodo.AudioTag-spks",
    "com.foyoodo.AudioTag-spki",
}
if not needed.issubset(set(lookup)):
    raise SystemExit(f"Sparkle mach-lookup ports missing; have {lookup!r}")
PY
echo "Sandbox entitlement com.apple.security.app-sandbox is present and true."
echo "Sparkle mach-lookup exceptions -spks and -spki are present."

echo "=== Sparkle Info.plist keys ==="
python3 - "$INFO_PLIST" <<'PY'
import os, pathlib, plistlib, sys

info = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
feed = info.get("SUFeedURL")
print("SUFeedURL =", feed)
if not isinstance(feed, str) or not feed.startswith("https://"):
    raise SystemExit("SUFeedURL must be an https URL")

installer = info.get("SUEnableInstallerLauncherService")
print("SUEnableInstallerLauncherService =", installer)
if installer not in (True, "YES", "true", 1):
    raise SystemExit("SUEnableInstallerLauncherService must be true")

downloader = info.get("SUEnableDownloaderService")
print("SUEnableDownloaderService =", downloader)
if downloader not in (True, "YES", "true", 1):
    raise SystemExit("SUEnableDownloaderService must be true")

# The key must exist. Empty is allowed on PRs and main; a v* tag cannot ship
# clients that will never verify an update.
if "SUPublicEDKey" not in info:
    raise SystemExit("SUPublicEDKey is missing from Info.plist")
key = str(info.get("SUPublicEDKey") or "").strip()
is_version_tag = os.environ.get("GITHUB_REF", "").startswith("refs/tags/v")
if not key:
    if is_version_tag:
        raise SystemExit(
            "SUPublicEDKey is empty on a v* tag build. Set SPARKLE_PUBLIC_ED_KEY "
            "in Project.swift before tagging; shipped clients cannot be given a "
            "public key later."
        )
    print("SUPublicEDKey is empty (set SPARKLE_PUBLIC_ED_KEY before a v* tag)")
else:
    print("SUPublicEDKey is set")
PY

echo "=== Sparkle.framework and XPC services ==="
require_signed() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "::error::Missing $path"
    exit 1
  fi
  echo "codesign --verify --deep --strict $path"
  codesign --verify --deep --strict --verbose=2 "$path"
  codesign -dv --verbose=2 "$path" 2>&1 | sed -n '1,12p' || true
}

require_signed "$SPARKLE_FW"

found_installer=0
found_downloader=0
while IFS= read -r xpc; do
  [[ -z "$xpc" ]] && continue
  base="$(basename "$xpc")"
  require_signed "$xpc"
  case "$base" in
    Installer.xpc) found_installer=1 ;;
    Downloader.xpc) found_downloader=1 ;;
  esac
done < <(sparkle_paths "$SPARKLE_FW" "*.xpc")

if [[ "$found_installer" -ne 1 ]]; then
  echo "::error::Sparkle Installer.xpc is missing (required for the App Sandbox)"
  exit 1
fi
if [[ "$found_downloader" -ne 1 ]]; then
  echo "::error::Sparkle Downloader.xpc is missing (required without network.client)"
  exit 1
fi

while IFS= read -r helper; do
  [[ -z "$helper" ]] && continue
  require_signed "$helper"
done < <(sparkle_paths "$SPARKLE_FW" "Autoupdate")

while IFS= read -r updater; do
  [[ -z "$updater" ]] && continue
  require_signed "$updater"
done < <(sparkle_paths "$SPARKLE_FW" "Updater.app")

echo "Sparkle.framework, Installer.xpc, and Downloader.xpc are present and signed."

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
