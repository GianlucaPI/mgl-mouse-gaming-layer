import Foundation

public enum MGL {
    public static let version = "0.1.0-dev"

    /// SteelSeries vendor IDs: 0x1038 over USB / 2.4 GHz dongle,
    /// 0x0111 over Bluetooth LE (Bluetooth SIG-assigned company ID).
    public static let steelSeriesVendorIDs = [0x1038, 0x0111]

    /// Stored in `eventSourceUserData` of every event MGL posts ("MGL" in ASCII),
    /// so our own taps can recognize and ignore them.
    public static let syntheticEventMarker: Int64 = 0x4D_47_4C
}

/// Monotonic clock shared by all monitors, so HID and event-tap logs can be interleaved.
public enum ProbeClock {
    private static let start = DispatchTime.now().uptimeNanoseconds

    /// Milliseconds elapsed since the process started using the clock.
    public static func elapsedMs() -> Double {
        let origin = start  // force lazy init *before* reading "now", or the result underflows
        return Double(DispatchTime.now().uptimeNanoseconds - origin) / 1_000_000
    }

    public static func stamp() -> String {
        String(format: "%11.3fms", elapsedMs())
    }
}

/// Parses "0x1038", "1038" (hex) or "#4152" (decimal).
public func parseHexInt(_ text: String) -> Int? {
    if text.hasPrefix("#") { return Int(text.dropFirst()) }
    let cleaned = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
    return Int(cleaned, radix: 16)
}

public func hex(_ value: Int, width: Int = 4) -> String {
    "0x" + String(format: "%0\(width)X", value)
}
