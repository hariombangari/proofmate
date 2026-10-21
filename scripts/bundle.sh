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

# Ad-hoc signature. No developer account needed. Gatekeeper is fine with
# locally built apps that were never quarantined.
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run with: open $APP"
