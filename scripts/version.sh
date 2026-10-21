#!/bin/bash
# Prints the app version. Sources/ProofMateCore/Version.swift is the single source of truth.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION_FILE="Sources/ProofMateCore/Version.swift"
VERSION=$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' "$VERSION_FILE")
if [ -z "$VERSION" ]; then
    echo "Could not read version from $VERSION_FILE" >&2
    exit 1
fi
echo "$VERSION"
