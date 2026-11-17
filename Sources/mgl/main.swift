import Foundation
import MGLCore

// mgl — the Mouse Gaming Layer (Phase 2, Strategy A).
// Adds the modifiers held on the real keyboard to key events that arrive without them
// (e.g. the Aerox 9 side buttons).

setvbuf(stdout, nil, _IOLBF, 0)

let usage = """
mgl \(MGL.version) — Mouse Gaming Layer

USAGE
  mgl [options]

OPTIONS
  --kbtype <n>   Only patch key events with this keyboardType (repeatable).
                 Find it with `mgl-probe watch` (Aerox 9 over BLE = 40).
                 Default: patch any key event missing a held modifier.
  --dry-run      Listen-only: log what would be patched, change nothing.
  -v, --verbose  Log every patched event.
  -h, --help     Show this help.

Requires Accessibility permission for the app that runs it (Terminal, …).
Press Ctrl-C to stop.
"""

var options = ModifierPatcher.Options()
var verbose = false

var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "--kbtype":
        i += 1
        guard i < args.count, let n = Int(args[i]) else {
            fputs("--kbtype needs an integer\n", stderr); exit(2)
        }
        options.keyboardTypes = (options.keyboardTypes ?? []).union([n])
    case "--dry-run": options.dryRun = true
    case "-v", "--verbose": verbose = true
    case "-h", "--help", "help": print(usage); exit(0)
    default: fputs("Unknown option \(args[i])\n\n\(usage)\n", stderr); exit(2)
    }
    i += 1
}

if !options.dryRun && !Permissions.accessibilityGranted {
    _ = Permissions.requestAccessibility()
    fputs("""
    Accessibility permission is required.
    System Settings → Privacy & Security → Accessibility: enable your terminal app,
    then restart the terminal and run mgl again. (Use --dry-run to test without it.)

    """, stderr)
    exit(1)
}

let patcher = ModifierPatcher(options: options) { patch in
    guard verbose || options.dryRun else { return }
    let kind = patch.type == .keyDown ? "keyDown" : "keyUp  "
    print("\(ProbeClock.stamp()) \(options.dryRun ? "WOULD PATCH" : "patched") \(kind) "
        + "\(KeyNames.macKeyCode(patch.keyCode)) kbType=\(patch.keyboardType)  "
        + "\(ModifierFlags.describe(patch.original)) -> \(ModifierFlags.describe(patch.patched))")
}

do { try patcher.start() } catch {
    fputs("\(error)\n", stderr); exit(1)
}

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler {
    patcher.stop()
    print("\nStopped. Patched events: \(patcher.patchedCount), tap restarts: \(patcher.tapRestarts)")
    exit(0)
}
sigint.resume()

let scope = options.keyboardTypes.map { "keyboardType " + $0.sorted().map(String.init).joined(separator: ",") } ?? "all keyboards"
print("mgl \(MGL.version) running\(options.dryRun ? " (DRY RUN)" : "") — patching \(scope). Ctrl-C to stop.")
CFRunLoopRun()
