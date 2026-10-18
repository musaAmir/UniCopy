#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
NAME="UniCopy"
MODE="${1:-native}"
case "$MODE" in native) ARCHITECTURES=("$(uname -m)");; universal) ARCHITECTURES=(arm64 x86_64);; *) echo "Usage: ./build.sh [native|universal]"; exit 2;; esac
mkdir -p build
STAGING="$(mktemp -d "$PWD/build/.bundle.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# A stable certificate keeps Screen Recording approval across rebuilds and updates.
# Ad-hoc signing changes the app's identity on every build.
IDENTITY="${UNICOPY_SIGN_IDENTITY:-Musa Apps Signing}"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then SIGNED="signed by $IDENTITY"
else echo "warning: \"$IDENTITY\" certificate not found; signing ad-hoc." >&2; IDENTITY="-"; SIGNED="ad-hoc signed"; fi
# The Xcode SwiftPM backend records the deployment target as the SDK version.
# Native SwiftPM links the installed SDK, enabling modern AppKit styling.
BINS=()
for ARCH in "${ARCHITECTURES[@]}"; do
  swift build --build-system native -c release --arch "$ARCH" --scratch-path "build/spm-$ARCH"
  BINS+=("$(swift build --build-system native -c release --arch "$ARCH" --scratch-path "build/spm-$ARCH" --show-bin-path)")
done
INPUTS=()
for BIN in "${BINS[@]}"; do INPUTS+=("$BIN/$NAME"); done
lipo -create "${INPUTS[@]}" -output "$APP/Contents/MacOS/$NAME"
strip -x "$APP/Contents/MacOS/$NAME"
# Sparkle's universal framework keeps its own signature; the app is signed around it.
mkdir -p "$APP/Contents/Frameworks"
ditto "build/spm-${ARCHITECTURES[0]}/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
if [[ "$NAME" == UniCopy ]]; then
  mkdir -p "$APP/Contents/Helpers"
  INPUTS=()
  for BIN in "${BINS[@]}"; do INPUTS+=("$BIN/UniCopyOCR"); done
  lipo -create "${INPUTS[@]}" -output "$APP/Contents/Helpers/UniCopyOCR"
  strip -x "$APP/Contents/Helpers/UniCopyOCR"
  codesign --force --sign "$IDENTITY" --timestamp=none "$APP/Contents/Helpers/UniCopyOCR"
fi
swift scripts/make-icon.swift "$NAME" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
# Replace only this script's build output.
rm -rf "build/$NAME.app"
mv "$APP" "build/$NAME.app"
echo "Built $PWD/build/$NAME.app ($MODE; $SIGNED, not notarized)"
