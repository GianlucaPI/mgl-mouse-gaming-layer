# MGL — Mouse Gaming Layer

**Hold Shift (or Option / Control / Command) on your keyboard, press a side button of your gaming mouse — and on macOS the game gets the plain key instead of the combination. MGL fixes that.**

A small menu-bar app for macOS. Built for the **SteelSeries Aerox 9** (12 side buttons) and **World of Warcraft**, on Apple Silicon.

## Is this your problem?

You probably need MGL if **all** of these are true:

- you play on a **Mac**;
- your mouse's side buttons are assigned to **keyboard keys** (e.g. `1`, `2`, `3`… or `Q`, `E`…), typical of MMO mice;
- **`Shift` + side button** (or `Alt`/`Ctrl` + side button) does **not** trigger your `Shift`-bindings in the game — the game reacts as if you had pressed the side button alone.

| You do | Without MGL the game receives | With MGL the game receives |
|---|---|---|
| hold `Shift` + press side button mapped to `1` | `1` | `Shift+1` ✅ |
| hold `Alt` + press side button mapped to `2` | `2` | `Alt+2` ✅ |
| hold `Shift`, press a side button, then click | click (Shift lost) | `Shift`+click ✅ |
| turn the wheel by one notch | often nothing (needs ~3 notches) | one wheel step ✅ (`normalizeWheel`) |

Your keyboard, the mouse buttons themselves and every other app keep working exactly as before. MGL can be active **only while the game is in the foreground**.

> **Verified with:** SteelSeries Aerox 9 Wireless over Bluetooth, World of Warcraft, macOS on a MacBook Pro M1 Pro. Other mice whose side buttons send keyboard keys (Razer Naga, Logitech G600, Corsair Scimitar, the Aerox 9 over its 2.4 GHz dongle…) may have the same problem and should work, but are **not tested yet** — reports welcome.

> ⚠️ **Known issue:** `Shift` + **mouse wheel** bindings (`SHIFT-MOUSEWHEELUP/DOWN`) still do not work in WoW — macOS turns Shift + wheel into horizontal scrolling inside the game. Details and workarounds in [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md#1-shift--mouse-wheel-does-not-trigger-wow-bindings-shift-mousewheelup--shift-mousewheeldown).

> Status: **alpha (v0.1.0)** · [Roadmap](docs/ROADMAP.md) · [Changelog](CHANGELOG.md) · [TODO](TODO.md) · [Dev log](DEV_LOG.txt)

## Why it happens

A mouse with programmable side buttons that send keys shows up on macOS as an **extra keyboard**. macOS keeps modifier state **per device**: a key coming from the "mouse keyboard" carries that device's modifiers — none — even while you hold Shift on your real keyboard. Diagnostics with `mgl-probe` showed that, at that moment, even macOS's *global* modifier state reads "no modifiers". The vendor software for macOS (SteelSeries GG) offers no workaround.

## How MGL fixes it

1. An event tap watches the **real keyboard** and keeps track of which modifiers you are holding (MGL keeps its own state, because the system one is reset by the mouse).
2. Every key press that arrives **without** those modifiers — i.e. from the mouse — gets them added. Mouse clicks and scroll events are patched the same way.
3. The game sees `Shift+1`, `Alt+1`, `Ctrl+1`, …
4. A second tap, right before events reach the game, fixes mouse-wheel notches (`normalizeWheel`: one notch = one step; experimental `shiftScroll`).
5. Optional (`--sync-global`): also restores macOS's *global* modifier state, for software that queries it instead of reading the event.

It is a strict **1:1 remap** — one physical press, one keystroke — with no macros, no timing, no automation, and no access to game memory or files.

Profiles in a JSON config decide **when** MGL is active (e.g. only while World of Warcraft is in front) and **how** (which modifiers, mouse patching, wheel options).

## Requirements

- macOS 13+ on Apple Silicon (developed on MacBook Pro M1 Pro)
- Swift 5.9+ toolchain — Command Line Tools are enough for everything, including the app bundle (no Xcode needed)
- Permissions: **Accessibility** and **Input Monitoring** (System Settings → Privacy & Security)

## Menu-bar app (recommended)

```bash
./scripts/create-signing-identity.sh   # once: local self-signed code-signing certificate
./scripts/build-app.sh --install       # build MGL.app, sign it, copy to /Applications, launch
```

Then grant **Accessibility** to **MGL** (System Settings → Privacy & Security → Accessibility; the app prompts and waits). A mouse icon appears in the menu bar:

| Icon | Meaning |
|---|---|
| filled mouse | active (a profile matches the frontmost app) |
| outlined mouse | inactive in this app, or paused |
| warning triangle | missing permission or config error (details in the menu) |

Menu: current state · **Enabled** (pause/resume) · **Profile** (Automatic by frontmost app, or force one) · **Edit Config…** (creates it from the example if missing) · Show Config in Finder · Reload Config · **Launch at Login** · Open Accessibility Settings · Quit. The config file is watched and reloaded on save; an invalid file keeps the previous config and shows the error in the menu.

**Why the signing identity:** macOS remembers the Accessibility permission per code signature. Ad-hoc signatures change on every build (the permission would have to be granted again); the local certificate gives a stable signature (`identifier "local.mgl.MouseGamingLayer" and certificate leaf = …`). The certificate lives only in your login keychain and can be deleted with Keychain Access. `MGL_SIGN_IDENTITY=<name>` uses another identity (e.g. an Apple Development certificate).

## Build & run (CLI)

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
      "apps": ["com.blizzard.worldofwarcraft", "Wow", "World of Warcraft"],
      "modifiers": ["shift", "control", "option", "command"],
      "patchMouse": true,
      "shiftScroll": "system",
      "normalizeWheel": true,
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
| `shiftScroll` | *Experimental — does not fix WoW, see Known issues.* Shift + mouse wheel: `system` (AppKit turns it into horizontal scroll inside the app), `vertical-keep-shift` (keep vertical + Shift by presenting the notch as a precise scroll, which AppKit does not convert — for WoW `SHIFT-MOUSEWHEELUP/DOWN`), `vertical` (drop Shift from the scroll event — only for games that track Shift themselves). Case, spaces and `_` are tolerated | `system` |
| `normalizeWheel` | Make every wheel notch worth at least one line (macOS may report 0.1 per notch, so games need several notches to react) | `false` |

**Resolution:** the first enabled profile whose `apps` contains the frontmost app wins; otherwise the first enabled catch-all profile; otherwise mgl is inactive (events pass through untouched). MGL switches profile instantly when you change app. Use `mgl-probe apps` to discover an app's name and bundle ID.

Config commands: `mgl config init [--force]`, `mgl config path`, `mgl config show`, `mgl config check`. Both the app and the CLI reload the file automatically when it is saved (CLI: also `pkill -HUP mgl`). If the file is deleted, the built-in default (always active) applies again.

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

`mgl-probe` commands: `list`, `perms`, `apps`, `hid`, `tap`, `watch` (default), `appkit` (offline self-test of how AppKit converts scroll events). Options: `--steelseries`, `--vendor <hex>`, `--all-pages`, `--raw`, `--session`, `--late`. Run `mgl-probe help` for details.

> Permissions are granted to the **terminal app** you run it from (Terminal, iTerm…): add it under System Settings → Privacy & Security → **Input Monitoring** (for `mgl-probe`) and **Accessibility** (for `mgl`), then restart the terminal.

> With Command Line Tools only (no Xcode), use `./scripts/test.sh` instead of `swift test`: it passes the swift-testing macro plugin path that SwiftPM does not find on its own.

## Fair-play note

MGL performs **1:1 input remapping** (one physical press → one keystroke with modifiers). It does not implement macros, timed sequences or automation, and it does not read or modify any game memory or files. Do not extend it in that direction.

## Disclaimer

MGL is an independent, unofficial project provided "as is", without warranty of any kind (see [LICENSE](LICENSE)). **Use it at your own risk.** Whether third-party input software is acceptable is decided by each game's publisher and its terms of service; the authors cannot guarantee that using MGL complies with them, and are not responsible for any consequence on your game accounts.

## Trademarks

World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. SteelSeries and Aerox are trademarks of SteelSeries ApS. macOS is a trademark of Apple Inc. All other trademarks are the property of their respective owners. They are used here only to describe compatibility. **This project is not affiliated with, endorsed by, or sponsored by Blizzard Entertainment, SteelSeries or Apple.**

## Uninstall

```bash
./scripts/uninstall.sh --dry-run   # show what would be removed
./scripts/uninstall.sh             # MGL.app + Launch at Login, stops running MGL/mgl
./scripts/uninstall.sh --all       # also config, preferences, signing identity, Accessibility entry
```

## Project layout

```
MGL_mouse_gaming_layer/
├── Package.swift
├── Sources/
│   ├── MGLCore/        # engine, event tap, config/profiles, HID tools, key & modifier tables
│   ├── mgl-probe/      # diagnostic CLI: lists HID devices, logs raw events
│   ├── mgl/            # the layer as a CLI (debugging, verbose logs)
│   └── MGLMenuBar/     # the menu-bar app (MGL.app)
├── Tests/MGLCoreTests/
├── config/example.json
├── Resources/AppIcon.icns
├── scripts/            # test.sh, build-app.sh, create-signing-identity.sh, uninstall.sh, make-icon.swift
├── .github/workflows/  # CI
├── docs/ROADMAP.md, docs/KNOWN_ISSUES.md
├── CHANGELOG.md, TODO.md, LICENSE
├── DEV_LOG.txt
└── README.md
```

## Development

- CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)): release build, unit tests, CLI smoke tests, ad-hoc signed `MGL.app` uploaded as a build artifact, uninstall dry run.
- Changes per version: [CHANGELOG.md](CHANGELOG.md) · planned work: [TODO.md](TODO.md) · open bugs: [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) · step-by-step history: [DEV_LOG.txt](DEV_LOG.txt).
- App icon: `swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.

## License

[MIT](LICENSE)
