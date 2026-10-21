#!/bin/bash
# Builds a release binary and wraps it in build/ProofMate.app.
#   UNIVERSAL=1     build arm64 + x86_64 (the release workflow sets this)
#   BUILD_NUMBER=n  CFBundleVersion (defaults to 1)
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_NUMBER="${BUILD_NUMBER:-1}"
if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "BUILD_NUMBER must be digits and dots, got: $BUILD_NUMBER" >&2
    exit 1
fi

VERSION=$(scripts/version.sh)
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
# bash 3.2 (macOS default) treats an empty array as unbound under `set -u`; this form is safe.
swift build -c release --product ProofMate ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR=$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

APP="build/ProofMate.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/ProofMate" "$APP/Contents/MacOS/ProofMate"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# Prefer a local self-signed "ProofMate Dev" identity: its designated requirement is
# stable across rebuilds, so the Accessibility grant survives. Ad-hoc signatures change
# with every build and macOS drops the grant. No developer account needed either way.
IDENTITY="${PROOFMATE_SIGN_IDENTITY:-ProofMate Dev}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "No \"$IDENTITY\" signing identity; using ad-hoc (Accessibility must be re-granted after each build)."
    codesign --force --sign - "$APP"
fi

echo "Built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/ProofMate"))"
