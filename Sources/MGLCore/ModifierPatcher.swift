import CoreGraphics
import Foundation

/// The MGL layer (Strategy A): an active CGEventTap that adds the modifiers held on the
/// real keyboard to key events that arrive without them (e.g. from the mouse).
/// Requires Accessibility permission.
public final class ModifierPatcher {
    public struct Options {
        /// Only patch key events whose keyboardType is in this set (nil = all).
        public var keyboardTypes: Set<Int>?
        /// Listen-only: compute and report patches without modifying events.
        public var dryRun: Bool

        public init(keyboardTypes: Set<Int>? = nil, dryRun: Bool = false) {
            self.keyboardTypes = keyboardTypes
            self.dryRun = dryRun
        }
    }

    public struct Patch {
        public let type: CGEventType
        public let keyCode: Int
        public let keyboardType: Int
        public let original: CGEventFlags
        public let patched: CGEventFlags
    }

    public private(set) var patchedCount = 0
    public private(set) var tapRestarts = 0

    private let options: Options
    private let onPatch: (Patch) -> Void
    private var tracker = ModifierTracker()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    public init(options: Options = Options(), onPatch: @escaping (Patch) -> Void = { _ in }) {
        self.options = options
        self.onPatch = onPatch
    }

    public func start() throws {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
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

    /// Hot path: keep it allocation-free and fast (the tap is disabled if it is slow).
    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .flagsChanged:
            let kbType = Int(event.getIntegerValueField(.keyboardEventKeyboardType))
            tracker.observeFlagsChanged(keyboardType: kbType, flags: event.flags)

        case .keyDown, .keyUp:
            let kbType = Int(event.getIntegerValueField(.keyboardEventKeyboardType))
            if let allowed = options.keyboardTypes, !allowed.contains(kbType) { return }
            let original = event.flags
            let patched = tracker.patched(original)
            guard patched != original else { return }
            if !options.dryRun { event.flags = patched }
            patchedCount += 1
            onPatch(Patch(
                type: type,
                keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                keyboardType: kbType,
                original: original,
                patched: patched
            ))

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // We may have missed modifier releases: drop state rather than risk stuck modifiers.
            tracker.reset()
            tapRestarts += 1
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        default:
            break
        }
    }
}
