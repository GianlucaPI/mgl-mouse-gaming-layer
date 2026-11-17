import CoreGraphics
import Foundation

/// One keyboard event as seen by the window server (after HID processing).
public struct TapKeyEvent {
    public let type: CGEventType
    public let keyCode: Int
    public let flags: CGEventFlags
    public let keyboardType: Int
    public let isAutorepeat: Bool
    public let sourceStateID: Int
    public let sourcePID: Int
    public let sourceUserData: Int
    /// Global modifier state as tracked by the HID system at the moment of the callback.
    public let hidSystemFlags: CGEventFlags
    /// Global modifier state of the combined session at the moment of the callback.
    public let sessionFlags: CGEventFlags
    public let timestampMs: Double
}

/// Listen-only CGEventTap for keyDown / keyUp / flagsChanged.
/// Requires Input Monitoring (listen-only) — Phase 2 will use an active tap (Accessibility).
public final class EventTapMonitor {
    public typealias Handler = (TapKeyEvent) -> Void

    private let handler: Handler
    private let location: CGEventTapLocation
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    public init(location: CGEventTapLocation = .cghidEventTap, handler: @escaping Handler) {
        self.location = location
        self.handler = handler
    }

    public func start() throws {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                if let context {
                    Unmanaged<EventTapMonitor>.fromOpaque(context).takeUnretainedValue().handle(type, event)
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

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        case .keyDown, .keyUp, .flagsChanged:
            break
        default:
            return
        }
        handler(TapKeyEvent(
            type: type,
            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags,
            keyboardType: Int(event.getIntegerValueField(.keyboardEventKeyboardType)),
            isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            sourceStateID: Int(event.getIntegerValueField(.eventSourceStateID)),
            sourcePID: Int(event.getIntegerValueField(.eventSourceUnixProcessID)),
            sourceUserData: Int(event.getIntegerValueField(.eventSourceUserData)),
            hidSystemFlags: CGEventSource.flagsState(.hidSystemState),
            sessionFlags: CGEventSource.flagsState(.combinedSessionState),
            timestampMs: ProbeClock.elapsedMs()
        ))
    }
}

extension CGEventType {
    public var shortName: String {
        switch self {
        case .keyDown: return "keyDown "
        case .keyUp: return "keyUp   "
        case .flagsChanged: return "flagsChg"
        default: return "type\(rawValue)"
        }
    }
}
