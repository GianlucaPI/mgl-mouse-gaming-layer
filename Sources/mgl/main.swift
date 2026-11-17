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

While running: send SIGHUP (`pkill -HUP mgl`) to reload the config.
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

/// Returns the config and whether it came from a file.
func loadConfig() throws -> (MGLConfig, fromFile: Bool) {
    guard FileManager.default.fileExists(atPath: configURL.path) else {
        return (MGLConfig.builtInDefault, false)
    }
    return (try MGLConfig.load(from: configURL), true)
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

var config: MGLConfig
do {
    let (loaded, fromFile) = try loadConfig()
    config = loaded
    print(fromFile ? "Config: \(configURL.path)"
                   : "Config: none at \(configURL.path) — built-in default (always active). `mgl config init` creates one.")
} catch { fail("\(error)", code: 1) }

if let forcedProfile, config.profile(named: forcedProfile) == nil {
    fail("No profile named \"\(forcedProfile)\"", code: 1)
}

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

let patcher = ModifierPatcher(settings: nil, dryRun: dryRun) { activity in
    guard verbose || dryRun else { return }
    switch activity {
    case let .patched(type, keyCode, kbType, original, patched):
        let what = keyCode >= 0 ? "\(eventName(type)) \(KeyNames.macKeyCode(keyCode)) kbType=\(kbType)" : eventName(type)
        print("\(ProbeClock.stamp()) \(dryRun ? "WOULD PATCH" : "patched") \(what)  "
            + "\(ModifierFlags.describe(original)) -> \(ModifierFlags.describe(patched))")
    case let .synced(flags, keyCode):
        print("\(ProbeClock.stamp()) synced global state \(ModifierFlags.describe(flags)) via \(KeyNames.macKeyCode(keyCode))")
    }
}

func describe(_ s: PatchSettings) -> String {
    let mods = ModifierName.allCases.filter { s.modifierMask & $0.mask != 0 }.map(\.rawValue).joined(separator: ",")
    var parts = ["modifiers=\(mods)"]
    if let k = s.keyboardTypes { parts.append("kbType=\(k.sorted().map(String.init).joined(separator: ","))") }
    parts.append(s.patchMouse ? "mouse=on" : "mouse=off")
    if s.syncGlobal { parts.append("sync-global") }
    return parts.joined(separator: " ")
}

var currentApp = FrontmostAppMonitor.current

/// Picks the profile for the frontmost app and applies it, logging only on changes.
func applyProfile(reason: String) {
    let profile = forcedProfile.flatMap(config.profile(named:))
        ?? config.resolve(bundleID: currentApp.bundleID, appName: currentApp.name)
    let settings = profile.map { PatchSettings(profile: $0).applying(overrides) }
    guard settings != patcher.settings || reason == "start" || reason == "reload" else { return }
    patcher.settings = settings
    if let settings {
        print("\(ProbeClock.stamp()) ACTIVE   profile \"\(settings.profileName)\" [\(describe(settings))] — \(currentApp.label)")
    } else {
        print("\(ProbeClock.stamp()) inactive (no profile) — \(currentApp.label)")
    }
}

do { try patcher.start() } catch { fail("\(error)", code: 1) }

let appMonitor = FrontmostAppMonitor { app in
    currentApp = app
    applyProfile(reason: "app")
}

print("mgl \(MGL.version) running\(dryRun ? " (DRY RUN)" : "")\(forcedProfile.map { " — forced profile \"\($0)\"" } ?? ""). Ctrl-C to stop.")
applyProfile(reason: "start")
appMonitor.start()

// SIGHUP: reload config. SIGINT/SIGTERM: stop with stats.
signal(SIGHUP, SIG_IGN)
let sighup = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
sighup.setEventHandler {
    do {
        config = try loadConfig().0
        print("\(ProbeClock.stamp()) config reloaded")
        applyProfile(reason: "reload")
    } catch {
        print("\(ProbeClock.stamp()) reload FAILED, keeping previous config: \(error)")
    }
}
sighup.resume()

var stopSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler {
        patcher.stop()
        appMonitor.stop()
        print("\nStopped. Patched keys: \(patcher.patchedKeyCount), mouse events: \(patcher.patchedMouseCount), "
            + "global syncs: \(patcher.syncCount), tap restarts: \(patcher.tapRestarts)")
        exit(0)
    }
    src.resume()
    stopSources.append(src)
}

CFRunLoopRun()
