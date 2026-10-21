#!/bin/bash
# Prints the app version. Sources/ProofMateCore/Version.swift is the single source of truth.
set -euo pipefail
cd "$(dirname "$0")/.."
sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/ProofMateCore/Version.swift
