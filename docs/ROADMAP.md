# MGL Roadmap

Goal: on macOS, holding a keyboard modifier (at minimum **Shift**, ideally Option/Ctrl/Cmd too) while pressing an Aerox 9 side button must produce `Modifier+Key` in World of Warcraft.

Stack: **Swift + SwiftPM** (no Xcode required until Phase 5), Apple frameworks only: `CoreGraphics` (CGEventTap / CGEvent), `IOKit.hid` (IOHIDManager), `AppKit` (frontmost app, menu bar), `ServiceManagement` (launch at login).

---

## Phase 0 — Repository & groundwork ✅
- [x] Git repo, README (EN), ROADMAP, DEV_LOG.txt, .gitignore
- [x] SwiftPM package skeleton (`MGLCore` library, `mgl-probe` and `mgl` executables, test target)
- [ ] Decide license

## Phase 1 — Diagnosis (`mgl-probe`) ✅
Confirm the exact root cause before writing the fix.
- [x] **HID enumeration**: list all HID devices with VendorID/ProductID/usage page. Identify the Aerox 9 (SteelSeries VID `0x1038`) interfaces: mouse, keyboard-like, vendor-specific. Note wired vs 2.4 GHz dongle vs Bluetooth (different PIDs).
- [x] **Raw HID log**: with `IOHIDManager`, print the key usages the mouse emits for each of the 12 side buttons (and whether it sends a modifier byte = 0 on every report).
- [x] **Event-tap log**: with a listen-only `CGEventTap`, print for every keyDown/keyUp/flagsChanged: keycode, `flags`, `kCGKeyboardEventKeyboardType`, source state ID, timestamp.
- [x] Summary on exit (presses per device, keyboardType stats, count of keyDowns missing a held modifier)
- [x] Test matrix (Shift + side buttons, Terminal): mouse keys arrive with no modifier flags; global HID/session state also reads empty. Mouse keyboardType = 40, MacBook keyboard = 92.
- [x] Findings in DEV_LOG.txt → Strategy A with MGL's own modifier tracking.

**Exit criterion:** we know which device/events carry the button presses and why modifiers are lost.

## Phase 2 — Core fix, Strategy A: flag-patching event tap (MVP) 🚧
The simplest approach; try first.
- [x] Active `CGEventTap` at `kCGHIDEventTap` for keyDown/keyUp/flagsChanged (`ModifierPatcher`).
- [x] Own modifier state per keyboardType from `flagsChanged` events, incl. left/right bits (`ModifierTracker`).
- [x] On keyDown/keyUp whose flags lack held modifiers → OR them into `event.flags` and pass the event on.
- [x] Tap timeouts: re-enable the tap and reset tracked state (avoid stuck modifiers).
- [x] Permission check & prompt (`AXIsProcessTrustedWithOptions`); `--dry-run`, `--kbtype`, `--verbose`.
- [x] Verify outside games: Shift+side button types uppercase in TextEdit and works in system apps.
- [x] Verify in WoW: `Shift+side button` triggers the Shift keybind.
- [ ] If WoW ignores event flags (reads global state): add a "sync" mode that also restores the global modifier state.

**Exit criterion:** Shift (and ideally Option/Ctrl) work with all 12 buttons in WoW.

## Phase 3 — Strategy B (fallback / robustness): seize & re-emit
Only if A is insufficient (e.g. WoW reads modifiers from a per-device state, or flags patching is ignored).
> ⚠️ Finding (2026-11-17): over Bluetooth LE the Aerox 9 exposes **one** HID interface carrying Mouse + Keyboard + Consumer + vendor collections. Seizing it would also swallow pointer movement and clicks, which would then have to be re-emitted too. Strategy A is strongly preferred; B is more viable over the 2.4 GHz dongle / USB if those expose a separate keyboard interface.
- [ ] Open the Aerox 9 keyboard interface with `IOHIDManager` using `kIOHIDOptionsTypeSeizeDevice` so macOS no longer sees its keystrokes.
- [ ] For each HID key usage from the mouse, synthesize a new `CGEvent` (keyDown/keyUp) with the current global modifier flags (`CGEventSourceFlagsState(.hidSystemState)` + own tracking) and post it.
- [ ] Map HID usage → macOS virtual keycode (table in `MGLCore`).
- [ ] Guarantee key-up delivery (no stuck keys) on sleep, device disconnect, app quit.
- [ ] Hot-plug support (dongle reconnect, wired/wireless switch).

## Phase 4 — Configuration & remapping
- [ ] JSON config (`~/Library/Application Support/MGL/config.json`): device match (VID/PID), enabled modifiers, optional per-button remap (e.g. side button → `F13`…`F24`, numpad keys).
- [ ] Per-app activation: active only while `World of Warcraft` is frontmost (`NSWorkspace.didActivateApplicationNotification`).
- [ ] Profiles (e.g. "WoW", "Default").
- [ ] Unit tests for modifier merging, keycode tables, config parsing.

## Phase 5 — Packaging & UX
- [ ] Menu-bar app (status item: on/off, profile, open config, quit).
- [ ] Launch at login (`SMAppService`).
- [ ] `.app` bundle with stable code signature (so macOS remembers Accessibility/Input Monitoring permissions across rebuilds). Ad-hoc or Developer ID; notarization optional for personal use.
- [ ] LaunchAgent alternative for a headless CLI setup.

## Phase 6 — Hardening & release
- [ ] Latency measurement (target: < 1 ms added per event).
- [ ] Edge cases: Secure Input (password fields disable taps), fast repeated presses, chords of two side buttons, key repeat.
- [ ] Logging levels, crash safety (never leave keys/modifiers stuck).
- [ ] v1.0 tag, CHANGELOG, release build instructions.

## Stretch goals
- Read/write Aerox 9 onboard key mappings via the vendor HID interface (replace SteelSeries GG for button assignment).
- Support other mice that act as keyboards (Razer Naga, Logitech G600, Corsair Scimitar…).

---

## Risks & notes
- **Permissions**: event taps need Accessibility; HID reading/seizing needs Input Monitoring. Unsigned rebuilds may lose granted permissions → sign consistently.
- **Game behavior**: WoW may read modifiers from the event flags or query state separately; Phase 1 tests in-game are essential.
- **Fair play**: strictly 1:1 remapping, no macros/automation.
