# TODO — to be implemented

Items agreed but not implemented yet. Details and history in [DEV_LOG.txt](DEV_LOG.txt); open bugs in [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

## High priority

- [ ] **`shiftScroll: "keys"` mode — real fix for Shift + mouse wheel in WoW** ([KNOWN_ISSUES #1](docs/KNOWN_ISSUES.md)).
  While Shift is held, turn each notched-wheel tick into a synthetic key press (e.g. Shift+F13 = wheel up, Shift+F14 = wheel down, configurable) and swallow the scroll event; the user binds those keys in WoW. Strict 1:1 remap (one notch → one key press).
  Notes: post key down + key up tagged with `MGL.syntheticEventMarker`; do it at the HID tap (before AppKit); keep `normalizeWheel` semantics for accelerated ticks (one key press per line?); tests for the mapping.

- [ ] **Stale-modifier guard.** If a modifier release is missed (e.g. Terminal's *Secure Keyboard Entry* / Secure Input hides key events from taps), `ModifierTracker` keeps the modifier "held" and MGL adds it to every key. Suspected cause of "Ctrl-C did not work in Terminal" (DEV_LOG 2026-11-17).
  Plan: evaluate `CGEventSourceKeyState` per modifier keycode (the `keys=` column of `mgl-probe`) — if it stays reliable while the mouse resets the modifier *flags*, drop tracked modifiers whose keys are not down before patching. Also reset the tracker when Secure Input turns on/off (`IsSecureEventInputEnabled`).

## Medium priority

- [ ] **Show a forced profile in the menu-bar icon/menu.** A profile forced from the Profile submenu stays forced across launches and makes MGL active in every app — easy to forget (it happened). Show e.g. "Forced: World of Warcraft" in the status line and a distinct icon/tooltip; optionally offer "Back to Automatic".

- [ ] **Warn when two layers run at once** (MGL.app + a CLI `mgl`, or two apps): both patch events. Detect another instance (e.g. `NSRunningApplication` / a lock file) and warn in the menu / CLI.

## Distribution

- [ ] **Notarization** (needs the paid Apple Developer Program, 99 $/year): Developer ID Application certificate, `codesign --options runtime`, `xcrun notarytool submit --wait` + `stapler staple` for app and DMG, in the release workflow. Removes the Gatekeeper "Open Anyway" step. See [docs/RELEASING.md](docs/RELEASING.md).
- [ ] **Homebrew cask** (own tap first; the official one increasingly expects notarized apps).
- [ ] **Auto-updates** with Sparkle (EdDSA update key, appcast published with each release).
- [ ] Optional: switch DMG creation from `hdiutil` (deprecated on macOS 27) to `diskutil image` once CI runners have it.

## Low priority / housekeeping

- [ ] Per-button remap (side button → F13…F24) — needs a freshly synthesized key event, not just a keycode change (ROADMAP Phase 4, deferred).
- [ ] Device match by VID/PID in the config (needs HID ↔ event correlation; `keyboardTypes` covers it for now).
- [ ] Local cleanup on the developer Mac: old config backups `~/Library/Application Support/MGL/config.json.bak` and `config.json.bak2` can be deleted.
