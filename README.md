# MGL — Mouse Gaming Layer

A lightweight macOS input layer that makes **keyboard modifiers (Shift, Option, Control, Command)** work together with the side buttons of gaming mice that emit keyboard keystrokes — built first and foremost for the **SteelSeries Aerox 9 (12 side buttons)** and **World of Warcraft** on Apple Silicon.

> Status: **pre-alpha — Phase 1 (diagnostics) tooling ready**. See [docs/ROADMAP.md](docs/ROADMAP.md) and [DEV_LOG.txt](DEV_LOG.txt).

## The problem

The Aerox 9 side buttons are mapped (in the mouse's onboard memory) to keyboard keys such as `1`–`=`. The mouse therefore enumerates on macOS as an additional **HID keyboard**.

When you hold `Shift` on your real keyboard and press a side button, the game receives the plain key (`1`) instead of `Shift+1`. On macOS, keyboard events carry modifier flags tied to the device that produced them, so a keystroke coming from the "mouse keyboard" arrives without the modifiers you are holding on the other device. SteelSeries GG for macOS does not offer a workaround.

## The idea

MGL sits between the hardware and the game:

1. It observes the keystrokes produced by the mouse (via a `CGEventTap` and, if needed, `IOHIDManager`).
2. It merges in the modifiers currently held on **any** keyboard.
3. It re-emits / patches the event so the game sees `Shift+1`, `Alt+1`, `Ctrl+1`, …

Optionally it can also remap the side buttons to arbitrary keys and only be active while World of Warcraft is in the foreground.

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
│   └── mgl/            # the layer daemon (stub until Phase 2)
├── Tests/MGLCoreTests/
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
```

`mgl-probe` commands: `list`, `perms`, `hid`, `tap`, `watch` (default). Options: `--steelseries`, `--vendor <hex>`, `--all-pages`, `--raw`, `--session`. Run `mgl-probe help` for details.

> Permissions are granted to the **terminal app** you run it from (Terminal, iTerm…): add it under System Settings → Privacy & Security → **Input Monitoring**, then restart the terminal.

> With Command Line Tools only (no Xcode), use `./scripts/test.sh` instead of `swift test`: it passes the swift-testing macro plugin path that SwiftPM does not find on its own.

## Fair-play note

MGL performs **1:1 input remapping** (one physical press → one keystroke with modifiers). It does not implement macros, timed sequences or automation, which keeps it in line with Blizzard's rules on input software. Do not extend it in that direction.

## License

TBD (MIT suggested).
