## Install

1. Download **ProofMate-<version>.dmg** below, open it, and drag ProofMate to Applications.
2. Open ProofMate. macOS blocks it the first time because it is not notarized by Apple.
   Open **System Settings → Privacy & Security**, scroll down to "ProofMate was blocked", and click **Open Anyway**.
   Or run in Terminal: `xattr -cr /Applications/ProofMate.app`
3. The setup window walks you through Accessibility access, Ollama, and choosing a model.

**Updating:** after replacing the app, repeat step 2. In System Settings → Privacy & Security → Accessibility,
remove ProofMate with − and add it again. Each release has a new signature, so the old grant no longer applies.
Upgrading from 0.1? The setup window opens once on first launch so you can check the new shortcut test.

Optional: verify the download with `shasum -a 256 -c ProofMate-<version>.dmg.sha256`.
