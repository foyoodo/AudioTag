#!/usr/bin/env bash
# Sign a Sparkle appcast for the universal zip with generate_appcast.
#
# Expected environment:
#   SPARKLE_ED_PRIVATE_KEY  base64 EdDSA private key (GitHub secret). If unset
#                           or empty, the script warns and exits 0 so the
#                           GitHub Release still publishes the zip/dmg assets.
#   GITHUB_REPOSITORY       owner/repo, e.g. foyoodo/AudioTag
#   GITHUB_REF_NAME         git tag, e.g. v0.1.1
#   DIST_DIR                directory with AudioTag-*-universal.zip (default: dist)
#   SPARKLE_TOOLS_VERSION   Sparkle distribution that provides generate_appcast
#                           (default: 2.9.1; must include --ed-key-file)
set -euo pipefail

DIST_DIR="${DIST_DIR:-dist}"
SPARKLE_TOOLS_VERSION="${SPARKLE_TOOLS_VERSION:-2.9.1}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
TAG="${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"
ASSET_ROOT="${DIST_DIR}/release-assets"

mkdir -p "$ASSET_ROOT"
# Zip/dmg names are AudioTag-<version>-<variant>.{zip,dmg}. Copy only those so
# a skipped appcast still leaves a non-empty release-assets directory.
shopt -s nullglob
packages=("$DIST_DIR"/AudioTag-*-arm64.zip "$DIST_DIR"/AudioTag-*-arm64.dmg \
  "$DIST_DIR"/AudioTag-*-universal.zip "$DIST_DIR"/AudioTag-*-universal.dmg)
if [[ ${#packages[@]} -eq 0 ]]; then
  echo "::error::No AudioTag zip/dmg packages found in $DIST_DIR"
  exit 1
fi
cp -f "${packages[@]}" "$ASSET_ROOT/"
shopt -u nullglob

trim() {
  # Strip leading/trailing whitespace without printing the value.
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

PRIVATE_KEY="$(trim "${SPARKLE_ED_PRIVATE_KEY:-}")"
if [[ -z "$PRIVATE_KEY" ]]; then
  echo "::warning::SPARKLE_ED_PRIVATE_KEY is not set; skipping Sparkle appcast. The zip and dmg will still be attached. Auto-updates will not be published for this release until the secret is configured and SPARKLE_PUBLIC_ED_KEY in Project.swift matches the public key."
  ls -lh "$ASSET_ROOT"
  exit 0
fi

shopt -s nullglob
universal_zips=("$DIST_DIR"/AudioTag-*-universal.zip)
shopt -u nullglob
if [[ ${#universal_zips[@]} -ne 1 ]]; then
  echo "::error::Expected exactly one universal zip in $DIST_DIR (found ${#universal_zips[@]})"
  exit 1
fi
UNIVERSAL_ZIP="${universal_zips[0]}"
echo "Appcast archive: $UNIVERSAL_ZIP"

WORKDIR="$(mktemp -d)"
TOOLS="$(mktemp -d)"
EXTRACT="$(mktemp -d)"
trap 'rm -rf "$WORKDIR" "$TOOLS" "$EXTRACT"' EXIT
cp -f "$UNIVERSAL_ZIP" "$WORKDIR/"

echo "=== Download Sparkle $SPARKLE_TOOLS_VERSION tools ==="
TARBALL="$TOOLS/Sparkle-${SPARKLE_TOOLS_VERSION}.tar.xz"
curl -fsSL -o "$TARBALL" \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_TOOLS_VERSION}/Sparkle-${SPARKLE_TOOLS_VERSION}.tar.xz"
tar -xJf "$TARBALL" -C "$TOOLS"
xattr -cr "$TOOLS" 2>/dev/null || true

GENERATE_APPCAST="$(find "$TOOLS" -name generate_appcast -type f | head -1)"
if [[ -z "$GENERATE_APPCAST" || ! -x "$GENERATE_APPCAST" ]]; then
  # Some tarball layouts drop the executable bit; try the well-known path.
  if [[ -f "$TOOLS/bin/generate_appcast" ]]; then
    GENERATE_APPCAST="$TOOLS/bin/generate_appcast"
  fi
fi
if [[ -z "$GENERATE_APPCAST" || ! -f "$GENERATE_APPCAST" ]]; then
  echo "::error::generate_appcast not found in Sparkle ${SPARKLE_TOOLS_VERSION} distribution"
  find "$TOOLS" -maxdepth 3 -print
  exit 1
fi
chmod +x "$GENERATE_APPCAST"
echo "Using $GENERATE_APPCAST"

ditto -x -k "$UNIVERSAL_ZIP" "$EXTRACT"
APP_PLIST="$(find "$EXTRACT" -path '*/AudioTag.app/Contents/Info.plist' -type f | head -1)"
if [[ -z "$APP_PLIST" ]]; then
  echo "::error::AudioTag.app Info.plist not found inside $UNIVERSAL_ZIP"
  exit 1
fi
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_PLIST" 2>/dev/null || true)"
if [[ -z "$(trim "$PUBLIC_KEY")" ]]; then
  echo "::warning::SUPublicEDKey is empty in the packaged app. The appcast will be signed, but this build cannot verify updates until SPARKLE_PUBLIC_ED_KEY is set in Project.swift and a new version is released."
fi

DOWNLOAD_PREFIX="https://github.com/${REPO}/releases/download/${TAG}/"
RELEASE_LINK="https://github.com/${REPO}/releases/tag/${TAG}"
APPCAST_OUT="$ASSET_ROOT/appcast.xml"

echo "=== generate_appcast ==="
echo "download-url-prefix=$DOWNLOAD_PREFIX"
# The private key is passed on stdin (--ed-key-file -), never on argv or disk.
set +x
printf '%s\n' "$PRIVATE_KEY" | "$GENERATE_APPCAST" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "$RELEASE_LINK" \
  --maximum-deltas 0 \
  -o "$APPCAST_OUT" \
  "$WORKDIR"
unset PRIVATE_KEY

if [[ ! -f "$APPCAST_OUT" ]]; then
  echo "::error::generate_appcast did not write $APPCAST_OUT"
  ls -la "$WORKDIR"
  exit 1
fi

# Attach any delta patches if generate_appcast created them despite --maximum-deltas 0.
shopt -s nullglob
deltas=("$WORKDIR"/*.delta)
if [[ ${#deltas[@]} -gt 0 ]]; then
  cp -f "${deltas[@]}" "$ASSET_ROOT/"
fi
shopt -u nullglob

echo "Wrote $APPCAST_OUT"
ls -lh "$ASSET_ROOT"
# The appcast is public (EdDSA signatures, not the private key).
sed -n '1,80p' "$APPCAST_OUT"
