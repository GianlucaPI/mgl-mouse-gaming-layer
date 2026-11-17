# MGL — Mouse Gaming Layer

A lightweight macOS input layer that makes **keyboard modifiers (Shift, Option, Control, Command)** work together with the side buttons of gaming mice that emit keyboard keystrokes — built first and foremost for the **SteelSeries Aerox 9 (12 side buttons)** and **World of Warcraft** on Apple Silicon.

> Status: **alpha — working in World of Warcraft; Phase 4 (config & per-app profiles) implemented**. See [docs/ROADMAP.md](docs/ROADMAP.md) and [DEV_LOG.txt](DEV_LOG.txt).

## The problem

The Aerox 9 side buttons are mapped (in the mouse's onboard memory) to keyboard keys such as `1`–`=`. The mouse therefore enumerates on macOS as an additional **HID keyboard**.

When you hold `Shift` on your real keyboard and press a side button, the game receives the plain key (`1`) instead of `Shift+1`. On macOS, keyboard events carry modifier flags tied to the device that produced them, so a keystroke coming from the "mouse keyboard" arrives without the modifiers you are holding on the other device. Diagnostics showed that even macOS's *global* modifier state reads "no modifiers" at that moment. SteelSeries GG for macOS does not offer a workaround.

## The idea

MGL sits between the hardware and the game:

1. An active `CGEventTap` tracks, from `flagsChanged` events, which modifiers are held on each keyboard (MGL keeps its own state because the system one is unreliable here).
2. Every keyDown/keyUp that arrives without those modifiers (e.g. from the mouse) gets them added to its flags. Mouse clicks and scroll events are patched the same way, because after a side-button press macOS's global modifier state reads empty and a following Shift-click would otherwise lose Shift.
3. The game sees `Shift+1`, `Opt+1`, `Ctrl+1`, …
4. Optionally (`--sync-global`), MGL also restores macOS's *global* modifier state with a synthetic modifier event, for apps/addons that query the current modifier state instead of reading it from the event.

Profiles in a JSON config decide **when** MGL is active (e.g. only while World of Warcraft is in the foreground) and **how** (which modifiers, mouse patching, global sync).

## Requirements

- macOS 13+ on Apple Silicon (developed on MacBook Pro M1 Pro)
- Swift 5.9+ toolchain (Command Line Tools are enough for the CLI; full Xcode only needed later for the menu-bar app bundle)
- Permissions: **Accessibility** and **Input Monitoring** (System Settings → Privacy & Security)

## Project layout

```
MGL_mouse_gaming_layer/
├── Package.swift
├── Sources/
│   ├── MGLCore/        # HID enumeration/monitoring, event tap, key & modifier tables
│   ├── mgl-probe/      # diagnostic CLI: lists HID devices, logs raw events
│   └── mgl/            # the layer (CLI; menu-bar app in Phase 5)
├── Tests/MGLCoreTests/
├── config/example.json
├── scripts/test.sh
├── docs/ROADMAP.md
├── DEV_LOG.txt
└── README.md
```

## Build & run

```bash
swift build -c release
./scripts/test.sh                                   # unit tests
.build/release/mgl-probe list --steelseries         # find the mouse's HID interfaces
.build/release/mgl-probe perms                      # check / request permissions
.build/release/mgl-probe watch | tee probe.log      # HID + event-tap log, Ctrl-C for summary
.build/release/mgl --dry-run                        # show what would be patched, change nothing
.build/release/mgl config init                      # create the config (active only in WoW)
.build/release/mgl -v                               # run the layer (needs Accessibility)
```

## Configuration

`mgl config init` writes `~/Library/Application Support/MGL/config.json` (same content as [config/example.json](config/example.json)). Without a config file, mgl is always active with every modifier (the Phase 2 behavior).

```json
{
  "version": 1,
  "profiles": [
    {
      "name": "World of Warcraft",
      "enabled": true,
      "apps": ["com.blizzard.worldofwarcraft", "World of Warcraft"],
      "modifiers": ["shift", "control", "option", "command"],
      "patchMouse": true,
      "syncGlobal": false
    },
    { "name": "Everywhere else", "enabled": false, "apps": [] }
  ]
}
```

| Profile key | Meaning | Default |
|---|---|---|
| `name` | Unique profile name | required |
| `enabled` | Skip the profile when `false` | `true` |
| `apps` | Bundle IDs or app names (case-insensitive). Empty/missing = any app (catch-all) | catch-all |
| `modifiers` | Any of `shift`, `control`/`ctrl`, `option`/`opt`/`alt`, `command`/`cmd` | all four |
| `keyboardTypes` | Only patch key events from these keyboard types (Aerox 9 over BLE = `40`) | any |
| `patchMouse` | Patch mouse clicks / scroll | `true` |
| `syncGlobal` | Restore macOS's global modifier state (experimental) | `false` |

**Resolution:** the first enabled profile whose `apps` contains the frontmost app wins; otherwise the first enabled catch-all profile; otherwise mgl is inactive (events pass through untouched). MGL switches profile instantly when you change app. Use `mgl-probe apps` to discover an app's name and bundle ID.

Config commands: `mgl config init [--force]`, `mgl config path`, `mgl config show`, `mgl config check`. Reload a running mgl with `pkill -HUP mgl`.

`mgl` run options (they override every profile):

| Option | Effect |
|---|---|
| `--config <path>` | Use another config file |
| `--profile <name>` | Force a profile, regardless of the frontmost app (even a disabled one) |
| `--kbtype <n>` | Only patch key events from that keyboardType (Aerox 9 over BLE = `40`) |
| `--no-mouse` | Don't patch mouse clicks / scroll (patched by default) |
| `--sync-global` | Also restore macOS's global modifier state after a patched mouse key (opt-in, experimental: a synthetic modifier event may count towards "press Ctrl twice"-style shortcuts) |
| `--dry-run` | Log what would be patched, change nothing |
| `-v`, `--verbose` | Log every patched / synced event |

Verified so far (BLE): Shift + side button in TextEdit, World of Warcraft (keybinds and `[mod:shift]` macros) and macOS system apps; Shift-click right after a side button keeps Shift.

`mgl-probe` commands: `list`, `perms`, `apps`, `hid`, `tap`, `watch` (default). Options: `--steelseries`, `--vendor <hex>`, `--all-pages`, `--raw`, `--session`. Run `mgl-probe help` for details.

> Permissions are granted to the **terminal app** you run it from (Terminal, iTerm…): add it under System Settings → Privacy & Security → **Input Monitoring** (for `mgl-probe`) and **Accessibility** (for `mgl`), then restart the terminal.

> With Command Line Tools only (no Xcode), use `./scripts/test.sh` instead of `swift test`: it passes the swift-testing macro plugin path that SwiftPM does not find on its own.

## Fair-play note

MGL performs **1:1 input remapping** (one physical press → one keystroke with modifiers). It does not implement macros, timed sequences or automation, which keeps it in line with Blizzard's rules on input software. Do not extend it in that direction.

## License

TBD (MIT suggested).
