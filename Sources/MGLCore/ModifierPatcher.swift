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
    }

    /// Active settings; nil = inactive (pass-through).
    public var settings: PatchSettings?

    public private(set) var patchedKeyCount = 0
    public private(set) var patchedMouseCount = 0
    public private(set) var syncCount = 0
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
