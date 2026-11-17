import CoreGraphics
import Foundation

/// The MGL layer (Strategy A): an active CGEventTap that adds the modifiers held on the
/// real keyboard to events that arrive without them (e.g. the mouse's side-button keys).
/// Requires Accessibility permission.
///
/// Behavior is driven by `settings`, which can change at runtime (profile switch);
/// `nil` means inactive: events pass through untouched, but modifier tracking continues
/// so the state is correct the moment a profile becomes active.
public final class ModifierPatcher {
    public enum Activity {
        case patched(type: CGEventType, keyCode: Int, keyboardType: Int,
                     original: CGEventFlags, patched: CGEventFlags)
        case synced(flags: CGEventFlags, keyCode: Int)
        /// A notched-wheel tick adjusted at the late stage (Shift handling / normalization).
        case wheelFixed(before: ScrollAxes, after: ScrollAxes, original: CGEventFlags,
                        patched: CGEventFlags, precise: Bool)
    }

    /// Active settings; nil = inactive (pass-through).
    public var settings: PatchSettings?

    public private(set) var patchedKeyCount = 0
    public private(set) var patchedMouseCount = 0
    public private(set) var syncCount = 0
    public private(set) var scrollFixCount = 0
    public private(set) var tapRestarts = 0

    private static let types: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged,
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp, .scrollWheel,
    ]

    private let dryRun: Bool
    private let onActivity: (Activity) -> Void
    private var tracker = ModifierTracker()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Second tap, at the last stage before apps (annotated session), for scroll events only:
    /// it sees the final wheel values (after macOS's scroll processing), which is where the
    /// wheel fixes belong. AppKit's Shift → horizontal conversion happens later, inside the
    /// app, so it is avoided by marking the tick as precise (DEV_LOG 2026-11-17).
    private var lateTap: CFMachPort?
    private var lateSource: CFRunLoopSource?
    private var syncPending = false
    private lazy var syntheticSource = CGEventSource(stateID: .hidSystemState)

    /// - Parameter dryRun: listen-only; report patches without modifying or posting events.
    public init(settings: PatchSettings?, dryRun: Bool = false,
                onActivity: @escaping (Activity) -> Void = { _ in }) {
        self.settings = settings
        self.dryRun = dryRun
        self.onActivity = onActivity
    }

    public func start() throws {
        let mask = Self.types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: dryRun ? .listenOnly : .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                if let context {
                    Unmanaged<ModifierPatcher>.fromOpaque(context).takeUnretainedValue().handle(type, event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else { throw MGLError.eventTapCreationFailed }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source

        guard let lateTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: dryRun ? .listenOnly : .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue,
            callback: { _, type, event, context in
                if let context {
                    Unmanaged<ModifierPatcher>.fromOpaque(context).takeUnretainedValue().handleLate(type, event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else { stop(); throw MGLError.eventTapCreationFailed }

        let lateSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, lateTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), lateSource, .commonModes)
        CGEvent.tapEnable(tap: lateTap, enable: true)
        self.lateTap = lateTap
        self.lateSource = lateSource
    }

    public func stop() {
        for (t, s) in [(tap, source), (lateTap, lateSource)] {
            if let t { CGEvent.tapEnable(tap: t, enable: false) }
            if let s { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .commonModes) }
        }
        tap = nil
        source = nil
        lateTap = nil
        lateSource = nil
    }

    /// Hot path: keep it fast (the tap is disabled by macOS if it is slow).
    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // We may have missed modifier releases: drop state rather than risk stuck modifiers.
            tracker.reset()
            tapRestarts += 1
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        // Never track or patch our own synthetic events.
        if event.getIntegerValueField(.eventSourceUserData) == MGL.syntheticEventMarker { return }

        if type == .flagsChanged {
            let kbType = Int(event.getIntegerValueField(.keyboardEventKeyboardType))
            tracker.observeFlagsChanged(keyboardType: kbType, flags: event.flags)
            return
        }
        guard let settings else { return }  // inactive: pass-through

        switch type {
        case .keyDown, .keyUp:
            let kbType = Int(event.getIntegerValueField(.keyboardEventKeyboardType))
            if let allowed = settings.keyboardTypes, !allowed.contains(kbType) { return }
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            guard patch(event, type: type, keyCode: keyCode, keyboardType: kbType, mask: settings.modifierMask)
            else { return }
            patchedKeyCount += 1
            // A key without the held modifiers means the global state was just reset.
            if settings.syncGlobal && !dryRun { scheduleSync() }

        default:  // mouse buttons and scroll
            guard settings.patchMouse else { return }
            if patch(event, type: type, keyCode: -1, keyboardType: -1, mask: settings.modifierMask) {
                patchedMouseCount += 1
            }
        }
    }

    /// Late stage: final wheel values, right before the app receives the event.
    private func handleLate(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapRestarts += 1
            if let lateTap { CGEvent.tapEnable(tap: lateTap, enable: true) }
            return
        }
        guard type == .scrollWheel, let settings,
              settings.shiftScroll != .system || settings.normalizeWheel,
              event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0  // notched wheels only
        else { return }

        let before = ScrollAxes(event: event)
        let original = event.flags
        let shiftMask = settings.modifierMask & ModifierName.shift.mask
        let heldShift = tracker.held.rawValue & shiftMask
        let result = WheelFix.apply(
            axes: before, flags: original,
            shiftHeld: heldShift != 0 || original.contains(.maskShift),
            heldShiftBits: heldShift, mode: settings.shiftScroll, normalize: settings.normalizeWheel)
        guard result.axes != before || result.flags != original || result.markContinuous else { return }
        if !dryRun {
            if result.axes != before { result.axes.write(to: event) }
            if result.flags != original { event.flags = result.flags }
            if result.markContinuous { event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1) }
        }
        scrollFixCount += 1
        onActivity(.wheelFixed(before: before, after: result.axes, original: original,
                               patched: result.flags, precise: result.markContinuous))
    }

    /// ORs held modifiers into the event. Returns true if the flags were missing some.
    private func patch(_ event: CGEvent, type: CGEventType, keyCode: Int, keyboardType: Int, mask: UInt64) -> Bool {
        let original = event.flags
        let patched = tracker.patched(original, mask: mask)
        guard patched != original else { return false }
        if !dryRun { event.flags = patched }
        onActivity(.patched(type: type, keyCode: keyCode, keyboardType: keyboardType,
                            original: original, patched: patched))
        return true
    }

    /// Runs after the current tap callback returns, i.e. after the mouse key event has been
    /// handed to the system. Tap callbacks and this block run serially on the same run
    /// loop, so a real modifier release that arrives first is already in `tracker` and
    /// one that arrives later simply follows our event: no stuck modifiers.
    private func scheduleSync() {
        guard !syncPending else { return }
        syncPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncPending = false
            self.postSync()
        }
    }

    private func postSync() {
        guard let settings else { return }
        let held = CGEventFlags(rawValue: tracker.held.rawValue & settings.modifierMask)
        guard let keyCode = ModifierFlags.representativeKeyCode(for: held),
              let event = CGEvent(keyboardEventSource: syntheticSource, virtualKey: keyCode, keyDown: true)
        else { return }
        event.type = .flagsChanged
        event.flags = CGEventFlags(rawValue: held.rawValue | ModifierFlags.nonCoalesced)
        event.setIntegerValueField(.eventSourceUserData, value: MGL.syntheticEventMarker)
        event.post(tap: .cghidEventTap)
        syncCount += 1
        onActivity(.synced(flags: held, keyCode: Int(keyCode)))
    }
}
