# Known issues

## 1. Shift + mouse wheel does not trigger WoW bindings (`SHIFT-MOUSEWHEELUP` / `SHIFT-MOUSEWHEELDOWN`)

**Status:** open · **Affects:** World of Warcraft (macOS), notched mouse wheels (verified with SteelSeries Aerox 9 over Bluetooth) · **Since:** always (macOS behavior, not introduced by MGL)

### Symptoms
- Wheel up / wheel down alone: work (needs `"normalizeWheel": true`, see below).
- Shift + middle click (wheel button): works.
- Shift + wheel up / down: **no binding fires** in WoW, with any `shiftScroll` mode.

### Root cause
AppKit — inside the game process, after every point where an external tool can intercept events — turns a *non-precise* (notched) scroll event with Shift into a **horizontal** scroll and keeps Shift. WoW therefore receives "Shift + wheel left/right" instead of "Shift + wheel up/down".

Evidence (see `DEV_LOG.txt`, 2026-11-17):
- `mgl-probe watch --late --steelseries`: at the last tap stage before the app (`kCGAnnotatedSessionEventTap`) the notch is still **vertical** with Shift (`axes: v=1/0.10/1px h=0`, `flags=[Shift(L)]`).
- `mgl-probe appkit` (offline, converts synthetic CGEvents with `NSEvent(cgEvent:)`, posts nothing):

| Scroll event | What the app reads |
|---|---|
| notch, no Shift (Aerox raw) | `deltaY=0.1` |
| notch + Shift | `deltaX=1, deltaY=0` — horizontal |
| horizontal-only notch + Shift | `deltaX=1` — AppKit never swaps back |
| precise notch + Shift | `deltaY=1`, Shift kept |
| notch with Shift removed | `deltaY=1`, no Shift |

### What was tried
| Attempt | Result in WoW |
|---|---|
| `shiftScroll: "vertical"` at the HID tap (strip Shift) | invalid test: the WindowServer recomputes scroll flags from the global state and put Shift back |
| `shiftScroll: "vertical-keep-shift"` at the HID tap (move axes back) | no effect: the notch is not yet horizontal there |
| late tap: move horizontal ticks back to vertical | no effect: the notch is still vertical at that stage (AppKit converts later) |
| late tap: present the notch as a **precise** scroll (keeps vertical + Shift at AppKit level) | WoW does not react — it apparently ignores or handles precise (trackpad-style) scrolls differently |
| late tap: strip Shift (`"vertical"`) | WoW sees a plain wheel — it takes wheel modifiers from the event |

### Related fix that did work
Each notch of the Aerox 9 reaches apps as only **0.1 line** (`deltaY=0.0999`), so WoW needed several notches before reacting. `"normalizeWheel": true` makes each notch worth one line: **single wheel notches now work on the first notch.**

### Workarounds
- Bind the wheel with another modifier in WoW (e.g. `ALT-MOUSEWHEELUP`); AppKit only converts Shift + wheel. (Ctrl + wheel can collide with macOS Accessibility zoom if enabled.)

### Possible fix (proposed, not implemented)
A `shiftScroll: "keys"` mode: while Shift is held, turn each wheel notch into a synthetic **key press** (e.g. Shift+F13 for up, Shift+F14 for down) and swallow the scroll event; the user binds those keys in WoW. Still a strict 1:1 remap (one notch → one key press), so within Blizzard's rules on input software.

### How to help diagnose
```bash
.build/release/mgl-probe appkit
.build/release/mgl-probe watch --late --steelseries | tee probe.log
```
