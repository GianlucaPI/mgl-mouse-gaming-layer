import AppKit
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
  apps      Log the frontmost app (name + bundle id) on every switch, for config "apps"
  hid       Log raw HID input values (keyboard, button, consumer pages)
  tap       Log key events, mouse clicks and scroll from a listen-only CGEventTap
  watch     hid + tap interleaved on one timeline (default)
  appkit    Offline self-test: how AppKit turns scroll events into what apps read
            (Shift + wheel → horizontal, precise vs notched). Posts nothing.

OPTIONS
  --vendor <hex>   Only HID devices with this vendor ID (e.g. 0x1038)
  --steelseries    SteelSeries only (0x1038 USB/dongle, 0x0111 Bluetooth)
  --all-pages      hid/watch: also log generic-desktop and vendor pages (noisy)
  --raw            hid/watch: also log non-key keyboard usages (rollover, 0x00-0x03)
  --session        tap/watch: tap at session level instead of HID level
                   (use it while mgl runs, to see events after mgl patched them)
  --late           tap/watch: tap at the last stage before apps (annotated session):
                   shows what apps really receive, e.g. Shift+wheel turned horizontal

Press Ctrl-C to stop; a summary is printed on exit. If Ctrl-C does not reach the
probe (e.g. the terminal is not focused), stop it with `pkill mgl-probe`.
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
    case "--late": tapLocation = .cgAnnotatedSessionEventTap
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
    case 0x01 where e.usage == 0x38:
        break  // wheel (other generic-desktop usages = pointer motion, too noisy)
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
        + (e.isMouse ? mouseDetail(e).padding(toLength: 21, withPad: " ", startingAt: 0)
            : "kc=\(String(e.keyCode).padding(toLength: 3, withPad: " ", startingAt: 0)) "
              + "(\(KeyNames.macKeyCode(e.keyCode)))".padding(toLength: 14, withPad: " ", startingAt: 0))
        + "flags=\(ModifierFlags.describeHex(e.flags))  kbType=\(e.keyboardType) "
        + "srcState=\(e.sourceStateID) pid=\(e.sourcePID)\(e.isAutorepeat ? " REPEAT" : "")  "
        + "held=\(ModifierFlags.describe(tracker.held)) hidState=\(ModifierFlags.describe(e.hidSystemFlags)) "
        + "session=\(ModifierFlags.describe(e.sessionFlags)) keys=\(physicalModifierKeys())"
        + (e.isSynthetic ? "  [MGL-SYNTH]" : "") + warn
        + (e.scroll.map { "  axes: \($0.summary)\(e.scrollIsContinuous ? " PRECISE" : " wheel")" } ?? "")
        + (e.scroll.map { $0.isHorizontalOnly && held.contains(.maskShift) ? "  <-- SHIFT→HORIZONTAL" : "" } ?? ""))

    if e.type == .keyDown {
        summary.tapKeyboardTypes[e.keyboardType, default: 0] += 1
        if !missing.isEmpty { summary.tapKeyDownsWithoutHeldModifiers += 1 }
    }
    if e.isMouse && !missing.isEmpty { summary.mouseDownsWithoutHeldModifiers += 1 }
    if e.isSynthetic { summary.syntheticEvents += 1 }
}

/// Modifier keys reported DOWN by CGEventSourceKeyState (per-key state, independent of the
/// modifier-flag state that the mouse's reports reset). Used to evaluate a stale-modifier guard.
func physicalModifierKeys() -> String {
    let keys: [(CGKeyCode, String)] = [(56, "LShift"), (60, "RShift"), (59, "LCtrl"), (62, "RCtrl"),
                                       (58, "LOpt"), (61, "ROpt"), (55, "LCmd"), (54, "RCmd")]
    let down = keys.filter { CGEventSource.keyState(.hidSystemState, key: $0.0) }.map(\.1)
    return "[" + down.joined(separator: " ") + "]"
}

func runAppKitSelfTest() {
    _ = NSApplication.shared
    func make(_ d1: Int32, _ d2: Int32, fixed1: Double, fixed2: Double, px1: Int64, px2: Int64,
              shift: Bool, precise: Bool) -> CGEvent? {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                              wheel1: d1, wheel2: d2, wheel3: 0) else { return nil }
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed1)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed2)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: px1)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: px2)
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
        e.flags = CGEventFlags(rawValue: shift ? 0x20102 : 0x100)
        return e
    }
    let cases: [(String, CGEvent?)] = [
        ("Aerox notch up, no Shift      ", make(1, 0, fixed1: 0.1, fixed2: 0, px1: 1, px2: 0, shift: false, precise: false)),
        ("Aerox notch up, Shift         ", make(1, 0, fixed1: 0.1, fixed2: 0, px1: 1, px2: 0, shift: true, precise: false)),
        ("normalized notch, Shift       ", make(1, 0, fixed1: 1, fixed2: 0, px1: 10, px2: 0, shift: true, precise: false)),
        ("horizontal-only notch, Shift  ", make(0, 1, fixed1: 0, fixed2: 1, px1: 0, px2: 10, shift: true, precise: false)),
        ("precise notch, Shift (keep)   ", make(1, 0, fixed1: 1, fixed2: 0, px1: 10, px2: 0, shift: true, precise: true)),
        ("notch, Shift stripped (vert.) ", make(1, 0, fixed1: 1, fixed2: 0, px1: 10, px2: 0, shift: false, precise: false)),
    ]
    print("What an app reads from NSEvent for each scroll event (nothing is posted):\n")
    for (name, cg) in cases {
        guard let cg, let ns = NSEvent(cgEvent: cg) else { print("\(name) -> (could not build)"); continue }
        print("\(name) -> deltaY=\(ns.deltaY) deltaX=\(ns.deltaX)  scrollingDeltaY=\(ns.scrollingDeltaY) "
            + "scrollingDeltaX=\(ns.scrollingDeltaX)  precise=\(ns.hasPreciseScrollingDeltas) "
            + "shift=\(ns.modifierFlags.contains(.shift))")
    }
}

func mouseDetail(_ e: TapKeyEvent) -> String {
    if let scroll = e.scroll {
        // Positive axis 1 = up, positive axis 2 = left (CGEvent convention).
        let v = scroll.fixed1 != 0 ? scroll.fixed1 : Double(scroll.delta1)
        let h = scroll.fixed2 != 0 ? scroll.fixed2 : Double(scroll.delta2)
        if v != 0 { return v > 0 ? "wheel up" : "wheel down" }
        if h != 0 { return h > 0 ? "wheel left" : "wheel right" }
        return "wheel 0"
    }
    switch e.buttonNumber {
    case 0: return "button 0 (left)"
    case 1: return "button 1 (right)"
    case 2: return "button 2 (middle)"
    default: return "button \(e.buttonNumber)"
    }
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
    let level = tapLocation == .cghidEventTap ? "HID" : (tapLocation == .cgSessionEventTap ? "session" : "annotated-session (late)")
    print("Event tap running at \(level) level.")
}

func installSigintSummary() {
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            summary.print()
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
}
var signalSources: [DispatchSourceSignal] = []

switch command {
case "list":
    runList()
case "apps":
    let monitor = FrontmostAppMonitor { app in
        print("\(ProbeClock.stamp()) frontmost: \(app.name ?? "?")  bundleID=\(app.bundleID ?? "-")  pid=\(app.pid)")
    }
    monitor.start()
    print("Switch between apps (e.g. WoW). Ctrl-C to stop.")
    CFRunLoopRun()
case "perms":
    runPerms()
case "appkit":
    runAppKitSelfTest()
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
