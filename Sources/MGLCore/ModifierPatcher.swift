import CoreGraphics
import Foundation

/// The MGL layer (Strategy A): an active CGEventTap that adds the modifiers held on the
/// real keyboard to events that arrive without them (e.g. the mouse's side-button keys).
/// Requires Accessibility permission.
public final class ModifierPatcher {
    public struct Options {
        /// Only patch key events whose keyboardType is in this set (nil = all).
        public var keyboardTypes: Set<Int>?
        /// Listen-only: compute and report patches without modifying or posting events.
        public var dryRun: Bool
        /// Also patch mouse button and scroll events. After a side-button key, macOS's
        /// global modifier state reads empty, so a following Shift-click may lose Shift.
        public var patchMouse: Bool
        /// After patching a key event, post a synthetic flagsChanged so that macOS's
        /// *global* modifier state (NSEvent.modifierFlags, CGEventSourceFlagsState)
        /// matches the modifiers actually held. Opt-in: synthetic modifier events can
        /// trigger "press modifier twice" shortcuts.
        public var syncGlobal: Bool

        public init(keyboardTypes: Set<Int>? = nil, dryRun: Bool = false,
                    patchMouse: Bool = true, syncGlobal: Bool = false) {
            self.keyboardTypes = keyboardTypes
            self.dryRun = dryRun
            self.patchMouse = patchMouse
            self.syncGlobal = syncGlobal
        }
    }

    public enum Activity {
        case patched(type: CGEventType, keyCode: Int, keyboardType: Int,
                     original: CGEventFlags, patched: CGEventFlags)
        case synced(flags: CGEventFlags, keyCode: Int)
    }

    public private(set) var patchedKeyCount = 0
    public private(set) var patchedMouseCount = 0
    public private(set) var syncCount = 0
    public private(set) var tapRestarts = 0

    private static let keyTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    private static let mouseTypes: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp, .scrollWheel,
    ]

    private let options: Options
    private let onActivity: (Activity) -> Void
    private var tracker = ModifierTracker()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var syncPending = false
    private lazy var syntheticSource = CGEventSource(stateID: .hidSystemState)

    public init(options: Options = Options(), onActivity: @escaping (Activity) -> Void = { _ in }) {
        self.options = options
        self.onActivity = onActivity
    }

    public func start() throws {
        let types = Self.keyTypes + (options.patchMouse ? Self.mouseTypes : [])
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: options.dryRun ? .listenOnly : .defaultTap,
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
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil
        source = nil
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

        switch type {
        case .flagsChanged:
            let kbType = Int(event.getIntegerValueField(.keyboardEventKeyboardType))
            tracker.observeFlagsChanged(keyboardType: kbType, flags: event.flags)

        case .keyDown, .keyUp:
            let kbType = Int(event.getIntegerValueField(.keyboardEventKeyboardType))
            if let allowed = options.keyboardTypes, !allowed.contains(kbType) { return }
            guard patch(event, type: type, keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                        keyboardType: kbType) else { return }
            patchedKeyCount += 1
            // A key without the held modifiers means the global state was just reset.
            if options.syncGlobal && !options.dryRun { scheduleSync() }

        default:  // mouse buttons and scroll (only subscribed when patchMouse is on)
            if patch(event, type: type, keyCode: -1, keyboardType: -1) { patchedMouseCount += 1 }
        }
    }

    /// ORs held modifiers into the event. Returns true if the flags were missing some.
    private func patch(_ event: CGEvent, type: CGEventType, keyCode: Int, keyboardType: Int) -> Bool {
        let original = event.flags
        let patched = tracker.patched(original)
        guard patched != original else { return false }
        if !options.dryRun { event.flags = patched }
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
        let held = tracker.held
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
