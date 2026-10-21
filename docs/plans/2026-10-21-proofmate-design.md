# ProofMate design

Date: 2026-10-21
Status: validated with Hari, ready for implementation planning

## Goal

A free, fully local Grammarly-style grammar and spelling corrector for macOS.
It works system-wide in any app through a global hotkey. No paid AI service.
The same app runs on two Macs: this M4 Pro with 24 GB RAM and a more
powerful laptop. Only the model name changes between them.

## Decisions made

| Question | Decision | Why |
|---|---|---|
| Where it works | System-wide, any app | Grammarly Desktop parity |
| Interaction | Global hotkey on selected text | Reliable across native, Electron, and browser apps. Days of work, not months |
| Engine | Ollama only, behind a protocol | Already installed. One engine handles fixes now and rewrite modes later |
| Result UX | Popover with word diff, Enter applies | User sees every change before it lands |
| Rewrite modes | Out of scope for v1 | Engine supports it; UI can add tabs later |

Rejected for v1: passive issue badges, live inline underlines (no sanctioned
way to draw inside other apps on macOS), Harper, LanguageTool, Apple
FoundationModels. All can slot in behind the engine protocol later.

## Architecture

Single native macOS menu bar app in Swift and SwiftUI. No Dock icon.
Not sandboxed: the App Sandbox blocks the Accessibility API and synthetic
keystrokes. Network access is localhost only.

Four parts:

1. **Hotkey listener.** Global shortcut, default Cmd+Shift+G, via Carbon
   `RegisterEventHotKey` wrapped in a small Swift class.
2. **Text capture and apply.** Try the Accessibility API first
   (`AXUIElement`, `kAXSelectedTextAttribute` on the focused element).
   If that fails (Chrome, many Electron apps), fall back to the clipboard:
   save the pasteboard, send Cmd+C, read it, restore it. Apply is the
   reverse: write the fix, send Cmd+V, restore the old clipboard. The
   clipboard is always restored, even on failure.
3. **Correction engine.** Protocol with one method, `correct(text)`
   returning the corrected text. v1 implementation: `OllamaEngine`
   calling `http://localhost:11434/api/chat` with streaming off and
   temperature 0. Model name and endpoint come from settings.
4. **Popover.** Floating `NSPanel` near the mouse pointer showing a
   word-level diff. Enter applies, Escape dismisses, Cmd+C copies.

Permission required: Accessibility, granted once in System Settings.

## Data flow

Hotkey pressed
→ capture selection
→ show popover immediately in a "Checking…" state
→ call Ollama
→ clean output, compute diff
→ render diff
→ Enter applies via paste, Escape dismisses

The popover appears before the model responds so the 1–2 s wait reads as
intentional. Empty selection shows "Select some text first" and closes
after two seconds.

## Prompt

System prompt, strict on purpose:

> Fix spelling, grammar, and punctuation only. Keep the author's words and
> tone. Do not add or remove ideas. Do not answer or explain the text.
> Return only the corrected text, nothing else.

User message is the raw selection. Temperature 0 for deterministic fixes.

Default model: a Qwen3 8B class model at Q4 (about 5 GB). The stronger
laptop uses a 14B or 32B model with no code change.

## Output guardrails

Small models sometimes wrap output in quotes, prepend "Here is the
corrected text:", or echo the input unchanged. `OutputCleaner`:

- strips wrapping quotes and known preambles
- trims whitespace
- treats an empty result, or one more than twice the input length, as a
  bad response and shows the original with a warning instead of applying

## Error handling

| Condition | Behaviour |
|---|---|
| Ollama not running | Popover says so, "Start Ollama" button runs the launch command |
| Model not pulled | Shows the `ollama pull` command |
| Timeout (20 s) | "Model took too long" with a retry button |
| Accessibility missing | One-time alert deep-linking to the right System Settings pane |
| Clipboard fallback fails | Previous clipboard restored, error shown |

## Project layout

Swift Package with a library target and an executable app target.

- `Sources/ProofMateCore/` — no UI, fully unit-testable
  - `CorrectionEngine.swift` — protocol
  - `OllamaEngine.swift` — HTTP client, error mapping
  - `OutputCleaner.swift` — quote and preamble stripping, sanity checks
  - `WordDiff.swift` — word-level diff for the popover
  - `Settings.swift` — model, endpoint, hotkey, loaded from JSON
- `Sources/ProofMate/` — the app
  - menu bar status item
  - `HotkeyManager.swift`
  - `TextCapture.swift` — Accessibility path and clipboard fallback
  - SwiftUI diff popover
- `Tests/ProofMateCoreTests/`
- `scripts/setup.sh` — checks Ollama, pulls the default model, builds

Settings live in a JSON file for v1. No settings window.

## Testing

- Unit tests (XCTest, no Ollama needed): `OutputCleaner` against a table
  of messy model outputs; `WordDiff` against known pairs; `OllamaEngine`
  against a stubbed `URLProtocol` verifying request body and error mapping.
- One opt-in integration test that hits real Ollama if running, skipped
  otherwise.
- Manual checklist for hotkey, Accessibility, and clipboard paths across
  TextEdit, Safari, Chrome, Slack, and Mail. This code is thin and cannot
  run without a window server.

## Second laptop

Clone, run `scripts/setup.sh`, change the model name in settings. Sign
with a local identity so Gatekeeper is quiet; no paid developer account.

## Out of scope for v1

Rewrite modes, passive badges, inline underlines, Harper, Apple's
on-device model, auto-updates, settings window.
