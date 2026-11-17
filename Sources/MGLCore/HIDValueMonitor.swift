import Foundation
import IOKit.hid

/// One input value received from a HID device.
public struct HIDInputEvent {
    public let device: HIDDeviceInfo
    public let usagePage: Int
    public let usage: Int
    public let value: Int
    public let timestampMs: Double
}

/// Observes raw HID input values (non-exclusive: macOS still receives them).
/// Requires Input Monitoring for keyboard-like devices.
public final class HIDValueMonitor {
    public typealias Handler = (HIDInputEvent) -> Void

    private let manager: IOHIDManager
    private let handler: Handler
    private var deviceCache: [UnsafeMutableRawPointer: HIDDeviceInfo] = [:]

    public init(vendorIDs: [Int]? = nil, handler: @escaping Handler) {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.handler = handler
        HIDDeviceEnumerator.setMatching(manager, vendorIDs: vendorIDs)
    }

    /// Schedules on the current run loop and opens the manager.
    public func start() throws {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<HIDValueMonitor>.fromOpaque(context).takeUnretainedValue().handle(value)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw MGLError.hidOpenFailed(result) }
    }

    public func stop() {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func handle(_ value: IOHIDValue) {
        let stamp = ProbeClock.elapsedMs()
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let key = Unmanaged.passUnretained(device).toOpaque()
        let info = deviceCache[key] ?? {
            let info = HIDDeviceInfo(device: device)
            deviceCache[key] = info
            return info
        }()

        // Skip values too large for a 64-bit integer (e.g. long vendor buffers).
        guard IOHIDValueGetLength(value) <= 8 else { return }

        handler(HIDInputEvent(
            device: info,
            usagePage: Int(IOHIDElementGetUsagePage(element)),
            usage: Int(IOHIDElementGetUsage(element)),
            value: IOHIDValueGetIntegerValue(value),
            timestampMs: stamp
        ))
    }
}

public enum MGLError: Error, CustomStringConvertible {
    case hidOpenFailed(IOReturn)
    case eventTapCreationFailed

    public var description: String {
        switch self {
        case .hidOpenFailed(let code):
            let hint = code == kIOReturnNotPermitted
                ? " (not permitted: grant Input Monitoring to your terminal app)" : ""
            return "IOHIDManagerOpen failed: \(String(format: "0x%08X", code))\(hint)"
        case .eventTapCreationFailed:
            return "CGEvent.tapCreate failed (grant Input Monitoring / Accessibility to your terminal app)"
        }
    }
}
