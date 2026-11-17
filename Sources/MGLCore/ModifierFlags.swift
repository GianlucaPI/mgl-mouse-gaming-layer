import CoreGraphics

/// Human-readable decoding of `CGEventFlags`, including the device-dependent
/// left/right bits (from IOKit's NX_DEVICE*KEYMASK constants).
public enum ModifierFlags {
    // Device-dependent (side-specific) bits, low 16 bits of the flags.
    public static let leftControl: UInt64  = 0x0000_0001
    public static let leftShift: UInt64    = 0x0000_0002
    public static let rightShift: UInt64   = 0x0000_0004
    public static let leftCommand: UInt64  = 0x0000_0008
    public static let rightCommand: UInt64 = 0x0000_0010
    public static let leftOption: UInt64   = 0x0000_0020
    public static let rightOption: UInt64  = 0x0000_0040
    public static let rightControl: UInt64 = 0x0000_2000

    /// NX_NONCOALSESCEDMASK: set on ordinary hardware events.
    public static let nonCoalesced: UInt64 = 0x0000_0100

    /// Virtual keycode of one modifier key that is held in `flags`, preferring the exact
    /// side when the device-dependent bits say so. Order: Shift, Ctrl, Option, Command.
    /// Used as the keycode of synthetic flagsChanged events. nil if no modifier is held.
    public static func representativeKeyCode(for flags: CGEventFlags) -> CGKeyCode? {
        let raw = flags.rawValue
        let table: [(CGEventFlags, UInt64, CGKeyCode, CGKeyCode)] = [
            // (mask, right-side bit, left keycode, right keycode)
            (.maskShift, rightShift, 56, 60),
            (.maskControl, rightControl, 59, 62),
            (.maskAlternate, rightOption, 58, 61),
            (.maskCommand, rightCommand, 55, 54),
        ]
        for (mask, rightBit, left, right) in table where flags.contains(mask) {
            let leftBits = raw & (leftShift | leftControl | leftOption | leftCommand)
            let onlyRight = raw & rightBit != 0 && leftBits & leftBit(for: mask) == 0
            return onlyRight ? right : left
        }
        return nil
    }

    private static func leftBit(for mask: CGEventFlags) -> UInt64 {
        switch mask {
        case .maskShift: return leftShift
        case .maskControl: return leftControl
        case .maskAlternate: return leftOption
        default: return leftCommand
        }
    }

    /// The device-independent modifier mask MGL cares about.
    public static let relevantMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    public static func describe(_ flags: CGEventFlags) -> String {
        var parts: [String] = []
        let raw = flags.rawValue
        func side(_ l: UInt64, _ r: UInt64) -> String {
            switch (raw & l != 0, raw & r != 0) {
            case (true, true): return "(L+R)"
            case (true, false): return "(L)"
            case (false, true): return "(R)"
            default: return ""
            }
        }
        if flags.contains(.maskShift) { parts.append("Shift" + side(leftShift, rightShift)) }
        if flags.contains(.maskControl) { parts.append("Ctrl" + side(leftControl, rightControl)) }
        if flags.contains(.maskAlternate) { parts.append("Opt" + side(leftOption, rightOption)) }
        if flags.contains(.maskCommand) { parts.append("Cmd" + side(leftCommand, rightCommand)) }
        if flags.contains(.maskAlphaShift) { parts.append("CapsLock") }
        if flags.contains(.maskSecondaryFn) { parts.append("Fn") }
        if flags.contains(.maskNumericPad) { parts.append("NumPad") }

        // Device-dependent bits set without the matching device-independent bit:
        // a strong hint of inconsistent per-device modifier state.
        let orphans: [(UInt64, CGEventFlags, String)] = [
            (leftShift | rightShift, .maskShift, "Shift"),
            (leftControl | rightControl, .maskControl, "Ctrl"),
            (leftOption | rightOption, .maskAlternate, "Opt"),
            (leftCommand | rightCommand, .maskCommand, "Cmd"),
        ]
        for (bits, mask, name) in orphans where raw & bits != 0 && !flags.contains(mask) {
            parts.append("!orphan-\(name)")
        }
        return "[" + parts.joined(separator: " ") + "]"
    }

    public static func describeHex(_ flags: CGEventFlags) -> String {
        "0x" + String(flags.rawValue, radix: 16, uppercase: true) + " " + describe(flags)
    }
}
