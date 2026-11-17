# MGL — Mouse Gaming Layer

A lightweight macOS input layer that makes **keyboard modifiers (Shift, Option, Control, Command)** work together with the side buttons of gaming mice that emit keyboard keystrokes — built first and foremost for the **SteelSeries Aerox 9 (12 side buttons)** and **World of Warcraft** on Apple Silicon.

> Status: **planning / pre-alpha**. See [docs/ROADMAP.md](docs/ROADMAP.md) and [DEV_LOG.txt](DEV_LOG.txt).

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

## Project layout (planned)

```
MGL_mouse_gaming_layer/
├── Package.swift
├── Sources/
│   ├── MGLCore/        # event tap, modifier merging, device detection, config
│   ├── mgl-probe/      # diagnostic CLI: lists HID devices, logs raw events
│   └── mgl/            # the layer daemon (CLI first, menu-bar app later)
├── Tests/MGLCoreTests/
├── config/example.json
├── docs/ROADMAP.md
├── DEV_LOG.txt
└── README.md
```

## Build & run (once Phase 1 lands)

```bash
swift build -c release
.build/release/mgl-probe        # diagnostics
.build/release/mgl              # start the layer
```

## Fair-play note

MGL performs **1:1 input remapping** (one physical press → one keystroke with modifiers). It does not implement macros, timed sequences or automation, which keeps it in line with Blizzard's rules on input software. Do not extend it in that direction.

## License

TBD (MIT suggested).
