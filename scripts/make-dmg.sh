#!/bin/bash
# Packages build/ProofMate.app into build/ProofMate-<version>.dmg with an Applications link,
# plus a .sha256 file next to it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(scripts/version.sh)
APP="build/ProofMate.app"
NAME="ProofMate-$VERSION.dmg"
DMG="build/$NAME"
[ -d "$APP" ] || { echo "Missing $APP. Run scripts/bundle.sh first." >&2; exit 1; }
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
if [ "$APP_VERSION" != "$VERSION" ]; then
    echo "$APP is version $APP_VERSION but Version.swift says $VERSION. Run scripts/bundle.sh first." >&2
    exit 1
fi

STAGE=$(mktemp -d)
chmod 755 "$STAGE"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG" "$DMG.sha256"
# GitHub macOS runners sometimes fail hdiutil with "Resource busy" (actions/runner-images#7522).
ATTEMPTS=3
for attempt in $(seq 1 "$ATTEMPTS"); do
    if hdiutil create -volname "ProofMate $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null; then
        break
    fi
    if [ "$attempt" -eq "$ATTEMPTS" ]; then
        echo "hdiutil create failed $ATTEMPTS times; giving up on $DMG." >&2
        exit 1
    fi
    echo "hdiutil create failed (attempt $attempt of $ATTEMPTS); retrying in 5s." >&2
    sleep 5
done
(cd build && shasum -a 256 "$NAME" > "$NAME.sha256")

echo "Built $DMG"
cat "$DMG.sha256"
