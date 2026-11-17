import Foundation
import IOKit.hid

/// Snapshot of the properties of one HID device (interface).
public struct HIDDeviceInfo {
    public let vendorID: Int
    public let productID: Int
    public let product: String
    public let manufacturer: String
    public let transport: String
    public let locationID: Int
    public let primaryUsagePage: Int
    public let primaryUsage: Int
    public let usagePairs: [(page: Int, usage: Int)]
    public let maxInputReportSize: Int

    public init(device: IOHIDDevice) {
        func int(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? Int) ?? 0 }
        func str(_ key: String) -> String { (IOHIDDeviceGetProperty(device, key as CFString) as? String) ?? "?" }

        vendorID = int(kIOHIDVendorIDKey)
        productID = int(kIOHIDProductIDKey)
        product = str(kIOHIDProductKey)
        manufacturer = str(kIOHIDManufacturerKey)
        transport = str(kIOHIDTransportKey)
        locationID = int(kIOHIDLocationIDKey)
        primaryUsagePage = int(kIOHIDPrimaryUsagePageKey)
        primaryUsage = int(kIOHIDPrimaryUsageKey)
        maxInputReportSize = int(kIOHIDMaxInputReportSizeKey)

        let pairs = (IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]]) ?? []
        usagePairs = pairs.map {
            (page: ($0[kIOHIDDeviceUsagePageKey] as? Int) ?? 0,
             usage: ($0[kIOHIDDeviceUsageKey] as? Int) ?? 0)
        }
    }

    public var isKeyboardLike: Bool {
        usagePairs.contains { $0.page == 0x01 && ($0.usage == 0x06 || $0.usage == 0x07) }
    }

    public var isSteelSeries: Bool {
        MGL.steelSeriesVendorIDs.contains(vendorID) || manufacturer.localizedCaseInsensitiveContains("steelseries")
    }

    /// Short label used in event logs.
    public var shortLabel: String {
        "\(product) \(hex(vendorID)):\(hex(productID))@\(hex(locationID, width: 8))"
    }

    public static func usageName(page: Int, usage: Int) -> String {
        switch (page, usage) {
        case (0x01, 0x01): return "Pointer"
        case (0x01, 0x02): return "Mouse"
        case (0x01, 0x04): return "Joystick"
        case (0x01, 0x05): return "GamePad"
        case (0x01, 0x06): return "Keyboard"
        case (0x01, 0x07): return "Keypad"
        case (0x01, 0x80): return "SystemControl"
        case (0x0C, 0x01): return "ConsumerControl"
        case (0x0D, _): return "Digitizer"
        case (0xFF00...0xFFFF, _): return "Vendor(\(hex(page)):\(hex(usage)))"
        default: return "\(hex(page)):\(hex(usage))"
        }
    }

    public var usageSummary: String {
        let list = usagePairs.isEmpty ? [(primaryUsagePage, primaryUsage)] : usagePairs.map { ($0.page, $0.usage) }
        return list.map { Self.usageName(page: $0.0, usage: $0.1) }.joined(separator: ", ")
    }
}

public enum HIDDeviceEnumerator {
    /// Lists HID devices, optionally filtered by vendor IDs. Does not require any permission.
    public static func devices(vendorIDs: [Int]? = nil) -> [HIDDeviceInfo] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        setMatching(manager, vendorIDs: vendorIDs)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.map(HIDDeviceInfo.init(device:)).sorted {
            ($0.vendorID, $0.productID, $0.locationID, $0.primaryUsagePage, $0.primaryUsage)
                < ($1.vendorID, $1.productID, $1.locationID, $1.primaryUsagePage, $1.primaryUsage)
        }
    }

    /// nil = match every device.
    static func setMatching(_ manager: IOHIDManager, vendorIDs: [Int]?) {
        guard let vendorIDs else {
            IOHIDManagerSetDeviceMatching(manager, nil)
            return
        }
        let list = vendorIDs.map { [kIOHIDVendorIDKey: $0] }
        IOHIDManagerSetDeviceMatchingMultiple(manager, list as CFArray)
    }
}
