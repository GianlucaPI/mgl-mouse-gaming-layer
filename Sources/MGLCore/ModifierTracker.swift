import CoreGraphics

/// Tracks which modifiers are physically held, per keyboard type, from `flagsChanged` events.
///
/// Why per keyboard type: macOS's own global modifier state gets reset when a key arrives
/// from the mouse's keyboard collection (see DEV_LOG 2026-11-17), so we keep our own.
/// Each `flagsChanged` event carries the *complete* modifier state of the device that sent
/// it, so the state self-corrects on every modifier press/release.
public struct ModifierTracker {
    /// Device-independent modifier bits we propagate.
    public static let independentMask: UInt64 =
        CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue

    /// Device-dependent left/right bits (NX_DEVICE*KEYMASK).
    public static let dependentMask: UInt64 = 0x0000_207F

    public static let mask: UInt64 = independentMask | dependentMask

    private var perKeyboard: [Int: UInt64] = [:]

    public init() {}

    /// Update from a `flagsChanged` event.
    public mutating func observeFlagsChanged(keyboardType: Int, flags: CGEventFlags) {
        let bits = flags.rawValue & Self.mask
        if bits == 0 {
            perKeyboard.removeValue(forKey: keyboardType)
        } else {
            perKeyboard[keyboardType] = bits
        }
    }

    /// Union of modifiers currently held on any keyboard.
    public var held: CGEventFlags {
        CGEventFlags(rawValue: perKeyboard.values.reduce(0, |))
    }

    /// `flags` plus every held modifier allowed by `mask` (other bits untouched).
    public func patched(_ flags: CGEventFlags, mask: UInt64 = ModifierTracker.mask) -> CGEventFlags {
        CGEventFlags(rawValue: flags.rawValue | (held.rawValue & mask))
    }

    public mutating func reset() {
        perKeyboard.removeAll()
    }
}
