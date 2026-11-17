# Changelog

All notable changes to MGL. Format based on [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [0.1.0] — 2026-11-17

First release. Verified on a MacBook Pro M1 Pro with a SteelSeries Aerox 9 (Bluetooth) and World of Warcraft.

### Added
- **Modifier layer:** keyboard modifiers (Shift, Control, Option, Command, left/right aware) are added to key events from the mouse's side buttons, which macOS delivers without them. MGL tracks modifiers itself from `flagsChanged` events because macOS's global modifier state is reset by the mouse's own reports.
- Modifiers are also added to mouse clicks and scroll; optional `--sync-global` restores macOS's global modifier state.
- **Wheel:** `normalizeWheel` makes each notch worth one line (the Aerox 9 reports 0.1), so games react on the first notch.
- **Config** (`~/Library/Application Support/MGL/config.json`): per-app profiles (bundle ID or name), modifiers, keyboardTypes filter, mouse patching, wheel options; validation with readable errors; automatic reload on save.
- **Menu-bar app** `MGL.app`: status icon, pause, profile override, config editing, Launch at Login, permission handling.
- **CLI** `mgl` (same engine, verbose logs) and **diagnostics** `mgl-probe` (`list`, `perms`, `apps`, `hid`, `tap`, `watch`, `appkit`).
- Scripts: `build-app.sh` (no Xcode needed), `create-signing-identity.sh` (stable signature so Accessibility survives rebuilds), `uninstall.sh`, `make-icon.swift`, `test.sh`.
- CI on GitHub Actions, MIT license, app icon.

### Known issues
- Shift + mouse wheel bindings do not work in WoW (AppKit converts them to horizontal scroll inside the game). The experimental `shiftScroll` option does not fix it. See [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

[0.1.0]: ../../releases/tag/v0.1.0
