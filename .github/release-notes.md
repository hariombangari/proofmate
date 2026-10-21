## Install

1. Download **ProofMate-<version>.dmg** below, open it, and drag ProofMate to Applications.
2. Open ProofMate. macOS says it can't verify it: click **Done** (not Move to Trash).
   Then open **System Settings → Privacy & Security**, scroll to "ProofMate was blocked to protect your Mac",
   click **Open Anyway**, enter your password, and confirm **Open Anyway**.
   Or run in Terminal: `xattr -cr /Applications/ProofMate.app`
3. The setup window walks you through Accessibility access, Ollama, and choosing a model.

**Updating:** after replacing the app, repeat step 2. In System Settings → Privacy & Security → Accessibility,
remove ProofMate with − and add it again. Each release has a new signature, so the old grant no longer applies.
Upgrading from 0.1? The setup window opens once on first launch so you can check the new shortcut test.

Optional: verify the download. In the folder where you downloaded both files, run `shasum -a 256 -c ProofMate-<version>.dmg.sha256`.
