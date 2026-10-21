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

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "ProofMate $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
(cd build && shasum -a 256 "$NAME" > "$NAME.sha256")

echo "Built $DMG"
cat "$DMG.sha256"
