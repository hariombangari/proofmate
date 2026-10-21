# ProofMate

Free, local, Grammarly-style grammar and spelling correction for macOS.
Select text in any app, press **⌃⌥G** (Control+Option+G), review the diff, press Return.
Runs entirely on your Mac through [Ollama](https://ollama.com). No accounts, no cloud.

## Requirements

- Mac with Apple Silicon or Intel, macOS 14 or newer
- [Ollama](https://ollama.com/download) installed

## Install

### Download

1. Download **ProofMate-<version>.dmg** from the
   [latest release](https://github.com/hariombangari/proofmate/releases/latest), open it, and drag
   ProofMate to Applications.
2. Open ProofMate. macOS says it can't verify it: click **Done** (not Move to Trash).
   Then open **System Settings → Privacy & Security**, scroll to "ProofMate was blocked to protect your Mac",
   click **Open Anyway**, enter your password, and confirm **Open Anyway**.
   Or run in Terminal: `xattr -cr /Applications/ProofMate.app`
3. The setup window walks you through Accessibility access, Ollama, and choosing a model.

ProofMate is not notarized (there is no paid Apple Developer account behind it), so macOS blocks
the first launch. Step 2 is needed once per version.

**Updating:** after replacing the app, repeat step 2. In System Settings → Privacy & Security → Accessibility,
remove ProofMate with − and add it again. Each release has a new signature, so the old grant no longer applies.
Upgrading from 0.1? The setup window opens once on first launch so you can check the new shortcut test.

Optional: verify the download. Each release also has a `ProofMate-<version>.dmg.sha256` file.
In the folder where you downloaded both files, run `shasum -a 256 -c ProofMate-<version>.dmg.sha256`.
It prints `OK` when the DMG matches.

### Build from source

Needs Xcode 16+ or the Command Line Tools (for `swift build`).

```bash
git clone https://github.com/hariombangari/proofmate.git && cd proofmate
scripts/setup.sh
open build/ProofMate.app
```

`setup.sh` checks Ollama is running, pulls the model (`qwen3:8b`, about 5 GB), and builds
`build/ProofMate.app`. The setup window then opens and asks for Accessibility access.

## Use

1. Select text in any app.
2. Press ⌃⌥G.
3. A popover shows deletions in red and insertions in green.
4. **Return** pastes the fix over your selection. **⌘C** copies it instead. **Escape** dismisses.

The setup window opens on first launch. It checks Accessibility access and Ollama, lets you pick a
model, and lets you record a different shortcut. Open it again any time with **Settings…** in the
menu bar icon's menu. While it is open, pressing the shortcut runs a self-test instead of a check:
the window shows that the shortcut was received. If nothing shows, another app owns that shortcut.

The menu also has **Check Selection** (with the current shortcut) and **Quit ProofMate**.

## Settings

Change settings in the setup window (menu bar icon → **Settings…**). That is the normal way.

The settings are stored in `~/Library/Application Support/ProofMate/settings.json`, and editing
the file still works. Quit and relaunch ProofMate after editing it.

```json
{
  "endpoint": "http://localhost:11434",
  "model": "qwen3:8b",
  "timeoutSeconds": 20,
  "hasCompletedOnboarding": true,
  "hotkey": {
    "keyCode": 5,
    "carbonModifiers": 6144,
    "key": "G"
  }
}
```

- `hotkey` is ⌃⌥G here: `keyCode` is a Carbon virtual key code, and `carbonModifiers` adds up
  Carbon modifier bits (⌘ 256, ⇧ 512, ⌥ 2048, ⌃ 4096). It must include ⌘, ⌃, or ⌥; otherwise
  ProofMate uses the default. `key` is only the label shown in the menu. Recording the shortcut in
  the setup window is easier.
- `hasCompletedOnboarding: false` makes the setup window open on the next launch.

On a more powerful Mac, choose `qwen3:14b` (or `gemma3:12b`) after `ollama pull <model>`.
`ollama list` shows the models you have.

## Develop

```bash
swift test                                   # unit tests, no Ollama needed
PROOFMATE_INTEGRATION=1 swift test           # also hits the live Ollama
scripts/bundle.sh && open build/ProofMate.app
/usr/bin/log stream --info --predicate 'subsystem == "com.hari.proofmate"'
```

Use `/usr/bin/log`, not `log`: in zsh, `log` is a shell builtin.

Scripts:

- `scripts/version.sh` prints the version. `Sources/ProofMateCore/Version.swift` is the single
  source of the version. The scripts and the release workflow read it from there.
- `scripts/bundle.sh` builds and signs `build/ProofMate.app`. `UNIVERSAL=1` builds arm64 + x86_64
  (the release workflow sets it). `BUILD_NUMBER=n` sets `CFBundleVersion` (default 1).
- `scripts/make-dmg.sh` packages `build/ProofMate.app` into `build/ProofMate-<version>.dmg` with a
  `.sha256` file next to it.
- `scripts/make-dev-cert.sh` creates a self-signed "ProofMate Dev" signing identity in your login
  keychain. Run it once if you rebuild often. Without it, `bundle.sh` ad-hoc signs the app, and
  macOS drops the Accessibility grant every time the ad-hoc signature changes. With it, `bundle.sh`
  signs with that identity and the grant survives rebuilds.

**Release:**

1. Bump the version in `Sources/ProofMateCore/Version.swift` (and `Tests/ProofMateCoreTests/VersionTests.swift`).
2. Commit and push to `main`.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`

The tag starts the Release workflow on GitHub Actions (macos-15, Xcode 16.4). It checks that the
tag matches `Version.swift`, runs the tests, builds the universal app, and publishes the DMG and
its checksum to GitHub Releases. CI has no signing identity, so the release app is ad-hoc signed.

Layout:

- `Sources/ProofMateCore` — UI-free logic: settings, hotkey, Ollama client, model advice, output cleaning, word diff. Unit tested.
- `Sources/ProofMate` — the menu bar app: hotkey, text capture, popover, setup window, coordinator.
- `scripts` — build, package, and version scripts.
- `docs/plans` — design and implementation plans.

## Troubleshooting

- **Hotkey does nothing.** Open **Settings…** and press the shortcut. If the window does not show it
  as received, another app owns it: record a different one. If it is received but nothing happens
  outside the window, check that Accessibility is enabled for ProofMate. After an update (or a
  rebuild without the dev identity), remove ProofMate from the Accessibility list and add it again.
- **"Ollama is not running".** Open the Ollama app or run `ollama serve`.
- **"Model is not pulled".** Run the `ollama pull` command shown in the popover or the setup window.
- **Timeout on long text.** Raise `timeoutSeconds` in the settings file.
- **Nothing captured in a specific app.** Some apps block synthetic ⌘C. Copy the text manually,
  then press ⌃⌥G in a text field.

## Out of scope

Rewrite modes, inline underlines, passive badges, API keys and cloud servers, in-app model
download, notarization, Homebrew, auto-update.

## License

MIT. See [LICENSE](LICENSE).
