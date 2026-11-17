import CoreGraphics
import Foundation
import MGLCore

// mgl — the Mouse Gaming Layer.
// Adds the modifiers held on the real keyboard to events that arrive without them
// (e.g. the Aerox 9 side buttons), according to the profile of the frontmost app.

setvbuf(stdout, nil, _IOLBF, 0)

let usage = """
mgl \(MGL.version) — Mouse Gaming Layer

USAGE
  mgl [run] [options]          Run the layer (default command)
  mgl config init [--force]    Write the example config (active only in WoW)
  mgl config path              Print the config file path
  mgl config show              Print the effective config
  mgl config check             Validate the config file

RUN OPTIONS
  --config <path>    Config file (default: ~/Library/Application Support/MGL/config.json).
                     Without a config file, mgl is always active with all modifiers.
  --profile <name>   Force this profile, regardless of the frontmost app.
  --kbtype <n>       Only patch key events with this keyboardType (repeatable).
                     Overrides the profiles. Aerox 9 over BLE = 40.
  --no-mouse         Do not patch mouse clicks / scroll.
  --sync-global      Also restore macOS's global modifier state (opt-in, experimental).
  --dry-run          Listen-only: log what would be patched, change nothing.
  -v, --verbose      Log every patched / synced event.
  -h, --help         Show this help.

While running, the config file is watched and reloaded on save (or send SIGHUP).
Requires Accessibility permission for the app that runs it (Terminal, …).
"""

func fail(_ message: String, code: Int32 = 2) -> Never {
    fputs(message + "\n", stderr)
    exit(code)
}

// MARK: - Argument parsing

var argv = Array(CommandLine.arguments.dropFirst())
var command = "run"
var subcommand: String?
if let first = argv.first, !first.hasPrefix("-") {
    command = argv.removeFirst()
    if command == "config" {
        guard let sub = argv.first, !sub.hasPrefix("-") else { fail("mgl config needs: init, path, show or check") }
        subcommand = argv.removeFirst()
    }
}

var configURL = MGLConfig.defaultURL
var forcedProfile: String?
var overrides = PatchSettings.Overrides()
var dryRun = false
var verbose = false
var force = false

var i = 0
while i < argv.count {
    func value() -> String {
        i += 1
        guard i < argv.count else { fail("\(argv[i - 1]) needs a value") }
        return argv[i]
    }
    switch argv[i] {
    case "--config": configURL = URL(fileURLWithPath: (value() as NSString).expandingTildeInPath)
    case "--profile": forcedProfile = value()
    case "--kbtype":
        guard let n = Int(value()) else { fail("--kbtype needs an integer") }
        overrides.keyboardTypes = (overrides.keyboardTypes ?? []).union([n])
    case "--no-mouse": overrides.noMouse = true
    case "--sync-global": overrides.syncGlobal = true
    case "--dry-run": dryRun = true
    case "-v", "--verbose": verbose = true
    case "--force": force = true
    case "-h", "--help": print(usage); exit(0)
    default: fail("Unknown option \(argv[i])\n\n\(usage)")
    }
    i += 1
}

// MARK: - Config loading

func loadConfig() throws -> (MGLConfig, fromFile: Bool) {
    let loaded = try MGLEngine.loadConfig(at: configURL)
    return (loaded.config, loaded.fromFile)
}

// MARK: - config subcommands

if command == "config" {
    switch subcommand {
    case "path":
        print(configURL.path)
    case "init":
        if FileManager.default.fileExists(atPath: configURL.path) && !force {
            fail("\(configURL.path) already exists (use --force to overwrite)", code: 1)
        }
        do { try MGLConfig.example.write(to: configURL) } catch { fail("Cannot write config: \(error)", code: 1) }
        print("Wrote \(configURL.path)")
    case "show", "check":
        do {
            let (config, fromFile) = try loadConfig()
            if subcommand == "check" {
                print(fromFile ? "OK: \(configURL.path)" : "No config file at \(configURL.path) (built-in default in use)")
                for p in config.profiles {
                    let apps = p.isCatchAll ? "any app" : (p.apps ?? []).joined(separator: ", ")
                    print("  \(p.isEnabled ? "✓" : "✗") \(p.name) — \(apps)")
                }
            } else {
                if !fromFile { print("// built-in default (no file at \(configURL.path))") }
                FileHandle.standardOutput.write(try config.encoded())
            }
        } catch { fail("\(error)", code: 1) }
    default:
        fail("Unknown config command \(subcommand ?? "")\n\n\(usage)")
    }
    exit(0)
}

guard command == "run" else { fail("Unknown command \(command)\n\n\(usage)") }

// MARK: - run

if !dryRun && !Permissions.accessibilityGranted {
    _ = Permissions.requestAccessibility()
    fail("""
    Accessibility permission is required.
    System Settings → Privacy & Security → Accessibility: enable your terminal app,
    then restart the terminal and run mgl again. (Use --dry-run to test without it.)
    """, code: 1)
}

// Validate up front: the CLI refuses to start with an invalid config.
do {
    let (config, fromFile) = try loadConfig()
    print(fromFile ? "Config: \(configURL.path)"
                   : "Config: none at \(configURL.path) — built-in default (always active). `mgl config init` creates one.")
    if let forcedProfile, config.profile(named: forcedProfile) == nil {
        fail("No profile named \"\(forcedProfile)\"", code: 1)
    }
} catch { fail("\(error)", code: 1) }

func eventName(_ type: CGEventType) -> String {
    switch type {
    case .keyDown: return "keyDown"
    case .keyUp: return "keyUp"
    case .leftMouseDown: return "leftMouseDown"
    case .leftMouseUp: return "leftMouseUp"
    case .rightMouseDown: return "rightMouseDown"
    case .rightMouseUp: return "rightMouseUp"
    case .otherMouseDown: return "otherMouseDown"
    case .otherMouseUp: return "otherMouseUp"
    case .scrollWheel: return "scrollWheel"
    default: return "type\(type.rawValue)"
    }
}

func describe(_ s: PatchSettings) -> String {
    let mods = ModifierName.allCases.filter { s.modifierMask & $0.mask != 0 }.map(\.rawValue).joined(separator: ",")
    var parts = ["modifiers=\(mods)"]
    if let k = s.keyboardTypes { parts.append("kbType=\(k.sorted().map(String.init).joined(separator: ","))") }
    parts.append(s.patchMouse ? "mouse=on" : "mouse=off")
    if s.syncGlobal { parts.append("sync-global") }
    if s.shiftScroll != .system { parts.append("shift-scroll=\(s.shiftScroll.rawValue)") }
    return parts.joined(separator: " ")
}

let engine = MGLEngine(configURL: configURL, dryRun: dryRun, overrides: overrides) { activity in
    guard verbose || dryRun else { return }
    switch activity {
    case let .patched(type, keyCode, kbType, original, patched):
        let what = keyCode >= 0 ? "\(eventName(type)) \(KeyNames.macKeyCode(keyCode)) kbType=\(kbType)" : eventName(type)
        print("\(ProbeClock.stamp()) \(dryRun ? "WOULD PATCH" : "patched") \(what)  "
            + "\(ModifierFlags.describe(original)) -> \(ModifierFlags.describe(patched))")
    case let .synced(flags, keyCode):
        print("\(ProbeClock.stamp()) synced global state \(ModifierFlags.describe(flags)) via \(KeyNames.macKeyCode(keyCode))")
    case let .shiftScrollFixed(stage, before, after, original, patched):
        print("\(ProbeClock.stamp()) \(dryRun ? "WOULD FIX" : "fixed") shift-scroll [\(stage)]  \(before.summary) -> \(after.summary)  "
            + "\(ModifierFlags.describe(original)) -> \(ModifierFlags.describe(patched))")
    }
}
engine.forcedProfile = forcedProfile

// Log ACTIVE/inactive only when the effective settings change (or after a reload).
var lastLogged: PatchSettings??
var forceNextLog = true
engine.onEvent = { event in
    switch event {
    case .statusChanged(let status):
        guard forceNextLog || lastLogged.map({ $0 != status.settings }) ?? true else { return }
        forceNextLog = false
        lastLogged = .some(status.settings)
        if let settings = status.settings {
            print("\(ProbeClock.stamp()) ACTIVE   profile \"\(settings.profileName)\" [\(describe(settings))] — \(status.app.label)")
        } else {
            print("\(ProbeClock.stamp()) inactive (no profile) — \(status.app.label)")
        }
    case .configReloaded:
        if lastLogged != nil { print("\(ProbeClock.stamp()) config reloaded") }
        forceNextLog = true
    case .configReloadFailed(let error):
        print("\(ProbeClock.stamp()) reload FAILED, keeping previous config: \(error)")
    }
}

print("mgl \(MGL.version) running\(dryRun ? " (DRY RUN)" : "")\(forcedProfile.map { " — forced profile \"\($0)\"" } ?? ""). Ctrl-C to stop.")
do { try engine.start() } catch { fail("\(error)", code: 1) }
engine.watchConfigFile()

// SIGHUP: reload config (the file is also watched). SIGINT/SIGTERM: stop with stats.
signal(SIGHUP, SIG_IGN)
let sighup = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
sighup.setEventHandler { engine.reloadConfig() }
sighup.resume()

var stopSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler {
        engine.stop()
        let p = engine.patcher
        print("\nStopped. Patched keys: \(p.patchedKeyCount), mouse events: \(p.patchedMouseCount), "
            + "shift-scroll fixes: \(p.scrollFixCount), global syncs: \(p.syncCount), tap restarts: \(p.tapRestarts)")
        exit(0)
    }
    src.resume()
    stopSources.append(src)
}

CFRunLoopRun()
