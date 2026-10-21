#!/bin/bash
# One-shot setup for a fresh Mac: checks Ollama, pulls the model from settings, builds the app.
set -euo pipefail
cd "$(dirname "$0")/.."

SETTINGS="$HOME/Library/Application Support/ProofMate/settings.json"
MODEL="qwen3:8b"
if [ -f "$SETTINGS" ]; then
    MODEL=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("model","qwen3:8b"))' "$SETTINGS")
fi

if ! command -v ollama >/dev/null 2>&1; then
    echo "Ollama is not installed. Install from https://ollama.com/download then re-run." >&2
    exit 1
fi

if ! curl -s -m 2 localhost:11434/api/version >/dev/null; then
    echo "Ollama is not running. Starting it..."
    open -a Ollama || { echo "Could not start Ollama. Run 'ollama serve' in another terminal." >&2; exit 1; }
    sleep 3
fi

echo "Pulling model $MODEL (skips if already present)..."
ollama pull "$MODEL"

scripts/bundle.sh

echo
echo "Done. Launch with:  open build/ProofMate.app"
echo "Then grant Accessibility access when prompted, select text anywhere, and press Control+Option+G."
