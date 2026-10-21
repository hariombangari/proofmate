# ProofMate

Free, local, Grammarly-style grammar and spelling correction for macOS.
Select text in any app, press **⌃⌥G** (Control+Option+G), review the diff, press Return.
Runs entirely on your Mac through [Ollama](https://ollama.com). No accounts, no cloud.

## Requirements

- Apple Silicon Mac, macOS 14 or newer
- Xcode 16+ or Command Line Tools (for `swift build`)
- [Ollama](https://ollama.com/download) installed

## Install

```bash
git clone https://github.com/hariombangari/proofmate.git && cd proofmate
scripts/setup.sh
open build/ProofMate.app
```

`setup.sh` checks Ollama is running, pulls the model (`qwen3:8b`, about 5 GB), and builds
`build/ProofMate.app`.

On first use macOS asks for Accessibility access. Enable ProofMate in
System Settings → Privacy & Security → Accessibility. If ProofMate is not in the list,
press ⌃⌥G once to make it ask, or add `build/ProofMate.app` with the **+** button.

## Use

1. Select text in any app.
2. Press ⌃⌥G.
3. A popover shows deletions in red and insertions in green.
4. **Return** pastes the fix over your selection. **⌘C** copies it instead. **Escape** dismisses.

The menu bar icon also has **Check Selection** and **Open Settings File**.

## Settings

`~/Library/Application Support/ProofMate/settings.json`, created on first launch.
Open it from the menu bar icon.

```json
{
  "endpoint": "http://localhost:11434",
  "model": "qwen3:8b",
  "timeoutSeconds": 20
}
```

On a more powerful Mac, set `"model": "qwen3:14b"` (or `gemma3:12b`) and run
`ollama pull <model>`. Quit and relaunch ProofMate after editing. `ollama list` shows the
models you have.

## Develop

```bash
swift test                                   # unit tests, no Ollama needed
PROOFMATE_INTEGRATION=1 swift test           # also hits the live Ollama
scripts/bundle.sh && open build/ProofMate.app
/usr/bin/log stream --info --predicate 'subsystem == "com.hari.proofmate"'
```

Use `/usr/bin/log`, not `log`: in zsh, `log` is a shell builtin.

**Rebuilding often?** `bundle.sh` ad-hoc signs the app by default, and macOS drops the
Accessibility grant every time an ad-hoc signature changes. Run `scripts/make-dev-cert.sh`
once to create a self-signed "ProofMate Dev" signing identity in your login keychain.
`bundle.sh` then signs with it, and the grant survives rebuilds.

Layout:

- `Sources/ProofMateCore` — UI-free logic: settings, Ollama client, output cleaning, word diff. Unit tested.
- `Sources/ProofMate` — the menu bar app: hotkey, text capture, popover, coordinator.
- `docs/plans` — design and implementation plan.

## Troubleshooting

- **Hotkey does nothing.** Check Accessibility is enabled for ProofMate. After a rebuild
  without the dev identity, remove ProofMate from the list and add it again. If another app
  owns ⌃⌥G, change the default in `Sources/ProofMate/HotkeyManager.swift`.
- **"Ollama is not running".** Open the Ollama app or run `ollama serve`.
- **"Model is not pulled".** Run the `ollama pull` command shown in the popover.
- **Timeout on long text.** Raise `timeoutSeconds` in the settings file.
- **Nothing captured in a specific app.** Some apps block synthetic ⌘C. Copy the text manually,
  then press ⌃⌥G in a text field.

## Out of scope for v1

Rewrite modes, inline underlines, passive badges, settings window, configurable hotkey,
auto-update.
