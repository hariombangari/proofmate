#!/bin/bash
# Builds a release binary and wraps it in build/ProofMate.app, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ProofMate

APP="build/ProofMate.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ProofMate" "$APP/Contents/MacOS/ProofMate"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

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

echo "Built $APP"
echo "Run with: open $APP"
