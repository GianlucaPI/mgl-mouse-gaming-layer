import CoreGraphics
import Foundation
import MGLCore

// mgl-probe — Phase 1 diagnostic tool.
// Lists HID devices and logs raw HID values and window-server key events side by side,
// so we can see where the Aerox 9 side-button presses come from and which modifiers they carry.

setvbuf(stdout, nil, _IOLBF, 0)

let usage = """
mgl-probe \(MGL.version) — MGL diagnostics

USAGE
  mgl-probe <command> [options]

COMMANDS
  list      List HID devices (no permission needed)
  perms     Show (and request) Input Monitoring / Accessibility permissions
  hid       Log raw HID input values (keyboard, button, consumer pages)
  tap       Log key events and mouse clicks from a listen-only CGEventTap
  watch     hid + tap interleaved on one timeline (default)

OPTIONS
  --vendor <hex>   Only HID devices with this vendor ID (e.g. 0x1038)
  --steelseries    SteelSeries only (0x1038 USB/dongle, 0x0111 Bluetooth)
  --all-pages      hid/watch: also log generic-desktop and vendor pages (noisy)
  --raw            hid/watch: also log non-key keyboard usages (rollover, 0x00-0x03)
  --session        tap/watch: tap at session level instead of HID level
                   (use it while mgl runs, to see events after mgl patched them)

Press Ctrl-C to stop; a summary is printed on exit.
Tip: pipe to a file with `| tee probe.log`.
"""

// MARK: - Argument parsing

var args = Array(CommandLine.arguments.dropFirst())
let command = (args.first.map { !$0.hasPrefix("-") } ?? false) ? args.removeFirst() : "watch"

var vendorFilter: [Int]?
var allPages = false
var raw = false
var tapLocation: CGEventTapLocation = .cghidEventTap

var i = 0
while i < args.count {
    switch args[i] {
    case "--vendor":
        i += 1
        guard i < args.count, let v = parseHexInt(args[i]) else {
            fputs("--vendor needs a hex value\n", stderr); exit(2)
        }
        vendorFilter = [v]
    case "--steelseries": vendorFilter = MGL.steelSeriesVendorIDs
    case "--all-pages": allPages = true
    case "--raw": raw = true
    case "--session": tapLocation = .cgSessionEventTap
    case "-h", "--help": print(usage); exit(0)
    default: fputs("Unknown option \(args[i])\n\n\(usage)\n", stderr); exit(2)
    }
    i += 1
}

// MARK: - Summary bookkeeping

struct Summary {
    var hidKeyPresses: [String: [String: Int]] = [:]   // device -> key -> count
    var tapKeyboardTypes: [Int: Int] = [:]            // keyboardType -> keyDown count
    var tapKeyDownsWithoutHeldModifiers = 0           // keyDown whose flags lack held modifiers
    var mouseDownsWithoutHeldModifiers = 0            // mouse clicks whose flags lack held modifiers
    var syntheticEvents = 0                           // events posted by mgl (--sync-global)

    func print() {
        Swift.print("\n===== SUMMARY =====")
        Swift.print("HID key presses per device:")
        if hidKeyPresses.isEmpty { Swift.print("  (none)") }
        for (device, keys) in hidKeyPresses.sorted(by: { $0.key < $1.key }) {
            let list = keys.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
            Swift.print("  \(device)\n    \(list)")
        }
        Swift.print("Event-tap keyDown count per keyboardType:")
        if tapKeyboardTypes.isEmpty { Swift.print("  (none)") }
        for (type, count) in tapKeyboardTypes.sorted(by: { $0.key < $1.key }) {
            Swift.print("  keyboardType \(type): \(count)")
        }
        Swift.print("keyDown events missing a held modifier:     \(tapKeyDownsWithoutHeldModifiers)")
        Swift.print("mouse clicks missing a held modifier:       \(mouseDownsWithoutHeldModifiers)")
        Swift.print("synthetic MGL events seen (--sync-global):  \(syntheticEvents)")
    }
}

var summary = Summary()

// MARK: - Loggers

func logHID(_ e: HIDInputEvent) {
    switch e.usagePage {
    case 0x07:
        if !raw && !KeyNames.isRealKeyboardUsage(e.usage) { return }
    case 0x0C where e.usage == 0x238 && e.value == 0 && !raw:
        return  // AC Pan = 0, re-sent by the Aerox 9 in every report
    case 0x09, 0x0C:
        break
    default:
        if !allPages { return }
    }
    let name = KeyNames.hidUsage(page: e.usagePage, usage: e.usage)
    let state = e.value != 0 ? "DOWN" : "up  "
    let global = ModifierFlags.describe(CGEventSource.flagsState(.hidSystemState))
    print("\(String(format: "%11.3fms", e.timestampMs)) HID  \(state) \(name.padding(toLength: 12, withPad: " ", startingAt: 0)) "
        + "page=\(hex(e.usagePage, width: 2)) usage=\(hex(e.usage, width: 2)) val=\(e.value)  "
        + "globalMods=\(global)  dev=\(e.device.shortLabel)")

    if e.usagePage == 0x07 && e.value != 0 && KeyNames.isRealKeyboardUsage(e.usage) {
        summary.hidKeyPresses[e.device.shortLabel, default: [:]][name, default: 0] += 1
    }
}

// Own modifier tracking: macOS's global state is reset by the mouse's key reports,
// so it cannot be used to detect missing modifiers (DEV_LOG 2026-11-17).
var tracker = ModifierTracker()

func logTap(_ e: TapKeyEvent) {
    if e.type == .flagsChanged && !e.isSynthetic {
        tracker.observeFlagsChanged(keyboardType: e.keyboardType, flags: e.flags)
    }
    let held = tracker.held.intersection(ModifierFlags.relevantMask)
    let carried = e.flags.intersection(ModifierFlags.relevantMask)
    let missing = held.subtracting(carried)
    let warn = (e.type != .flagsChanged && !missing.isEmpty)
        ? "  <-- MISSING \(ModifierFlags.describe(missing))" : ""

    print("\(String(format: "%11.3fms", e.timestampMs)) TAP  \(e.type.shortName) "
        + (e.isMouse ? "-".padding(toLength: 21, withPad: " ", startingAt: 0)
            : "kc=\(String(e.keyCode).padding(toLength: 3, withPad: " ", startingAt: 0)) "
              + "(\(KeyNames.macKeyCode(e.keyCode)))".padding(toLength: 14, withPad: " ", startingAt: 0))
        + "flags=\(ModifierFlags.describeHex(e.flags))  kbType=\(e.keyboardType) "
        + "srcState=\(e.sourceStateID) pid=\(e.sourcePID)\(e.isAutorepeat ? " REPEAT" : "")  "
        + "held=\(ModifierFlags.describe(tracker.held)) hidState=\(ModifierFlags.describe(e.hidSystemFlags)) "
        + "session=\(ModifierFlags.describe(e.sessionFlags))"
        + (e.isSynthetic ? "  [MGL-SYNTH]" : "") + warn)

    if e.type == .keyDown {
        summary.tapKeyboardTypes[e.keyboardType, default: 0] += 1
        if !missing.isEmpty { summary.tapKeyDownsWithoutHeldModifiers += 1 }
    }
    if e.isMouse && !missing.isEmpty { summary.mouseDownsWithoutHeldModifiers += 1 }
    if e.isSynthetic { summary.syntheticEvents += 1 }
}

// MARK: - Commands

func runList() {
    let devices = HIDDeviceEnumerator.devices(vendorIDs: vendorFilter)
    print("Found \(devices.count) HID interface(s)\(vendorFilter.map { " for vendor " + $0.map { hex($0) }.joined(separator: "/") } ?? ""):\n")
    for d in devices {
        let marker = d.isSteelSeries ? (d.isKeyboardLike ? "★ " : "• ") : "  "
        print("\(marker)\(d.product)  [\(d.manufacturer)]")
        print("    VID:PID \(hex(d.vendorID)):\(hex(d.productID))  transport=\(d.transport)  "
            + "location=\(hex(d.locationID, width: 8))  maxInputReport=\(d.maxInputReportSize)B")
        print("    usages: \(d.usageSummary)\(d.isKeyboardLike ? "   <- acts as a KEYBOARD" : "")")
    }
    print("\n★ = SteelSeries interface that acts as a keyboard (likely carries the side-button keys)")
}

func runPerms() {
    print(Permissions.report())
    if !Permissions.inputMonitoringGranted {
        print("\nRequesting Input Monitoring… (System Settings → Privacy & Security → Input Monitoring)")
        Permissions.requestInputMonitoring()
    }
    print("\nNote: from a terminal, permissions are granted to the terminal app, which must be restarted afterwards.")
}

var hidMonitor: HIDValueMonitor?
var tapMonitor: EventTapMonitor?

func startHID() {
    let monitor = HIDValueMonitor(vendorIDs: vendorFilter, handler: logHID)
    do { try monitor.start() } catch {
        fputs("HID monitor: \(error)\n", stderr); exit(1)
    }
    hidMonitor = monitor
    print("HID monitor running\(vendorFilter.map { " (vendor " + $0.map { hex($0) }.joined(separator: "/") + ")" } ?? " (all devices)").")
}

func startTap() {
    let monitor = EventTapMonitor(location: tapLocation, handler: logTap)
    do { try monitor.start() } catch {
        fputs("Event tap: \(error)\n", stderr); exit(1)
    }
    tapMonitor = monitor
    print("Event tap running at \(tapLocation == .cghidEventTap ? "HID" : "session") level.")
}

func installSigintSummary() {
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    source.setEventHandler {
        summary.print()
        exit(0)
    }
    source.resume()
    sigintSource = source
}
var sigintSource: DispatchSourceSignal?

switch command {
case "list":
    runList()
case "perms":
    runPerms()
case "hid", "tap", "watch":
    print(Permissions.report())
    print("""

    Test protocol: for each side button, press it alone, then while holding Shift,
    then Option, then Ctrl. Compare with the same key on the real keyboard.

    """)
    if command != "tap" { startHID() }
    if command != "hid" { startTap() }
    installSigintSummary()
    print("Listening… (Ctrl-C to stop)\n")
    CFRunLoopRun()
case "help":
    print(usage)
default:
    fputs("Unknown command \(command)\n\n\(usage)\n", stderr)
    exit(2)
}
