import CoreGraphics
import Testing
@testable import MGLCore

@Suite struct KeyNamesTests {
    @Test func hidLettersAndDigits() {
        #expect(KeyNames.hidKeyboardUsage(0x04) == "A")
        #expect(KeyNames.hidKeyboardUsage(0x1D) == "Z")
        #expect(KeyNames.hidKeyboardUsage(0x1E) == "1")
        #expect(KeyNames.hidKeyboardUsage(0x26) == "9")
        #expect(KeyNames.hidKeyboardUsage(0x27) == "0")
        #expect(KeyNames.hidKeyboardUsage(0x2D) == "-")
        #expect(KeyNames.hidKeyboardUsage(0x2E) == "=")
        #expect(KeyNames.hidKeyboardUsage(0x68) == "F13")
        #expect(KeyNames.hidKeyboardUsage(0xE1) == "LeftShift")
    }

    @Test func realUsageFilter() {
        #expect(!KeyNames.isRealKeyboardUsage(0x01))
        #expect(KeyNames.isRealKeyboardUsage(0x1E))
        #expect(KeyNames.isModifierUsage(0xE5))
        #expect(!KeyNames.isRealKeyboardUsage(0xFFFF_FFFF))
    }

    @Test func macKeyCodes() {
        #expect(KeyNames.macKeyCode(18) == "1")
        #expect(KeyNames.macKeyCode(56) == "LeftShift")
        #expect(KeyNames.macKeyCode(999) == "kc999")
    }
}

@Suite struct ModifierFlagsTests {
    @Test func emptyFlags() {
        #expect(ModifierFlags.describe([]) == "[]")
    }

    @Test func leftShift() {
        let flags = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | ModifierFlags.leftShift)
        #expect(ModifierFlags.describe(flags) == "[Shift(L)]")
    }

    @Test func orphanDeviceBit() {
        let flags = CGEventFlags(rawValue: ModifierFlags.rightOption)
        #expect(ModifierFlags.describe(flags) == "[!orphan-Opt]")
    }
}

@Suite struct ModifierTrackerTests {
    let shiftL = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | ModifierFlags.leftShift)
    let nonCoalesced = CGEventFlags(rawValue: 0x100)

    @Test func patchesMouseKeyWhileShiftHeld() {
        var t = ModifierTracker()
        t.observeFlagsChanged(keyboardType: 92, flags: CGEventFlags(rawValue: shiftL.rawValue | 0x100))
        let patched = t.patched(nonCoalesced)
        #expect(patched.contains(.maskShift))
        #expect(patched.rawValue & ModifierFlags.leftShift != 0)
        #expect(patched.rawValue & 0x100 != 0)  // other bits kept
    }

    @Test func releaseClearsState() {
        var t = ModifierTracker()
        t.observeFlagsChanged(keyboardType: 92, flags: shiftL)
        t.observeFlagsChanged(keyboardType: 92, flags: nonCoalesced)
        #expect(t.held.isEmpty)
        #expect(t.patched(nonCoalesced) == nonCoalesced)
    }

    @Test func unionAcrossKeyboards() {
        var t = ModifierTracker()
        t.observeFlagsChanged(keyboardType: 92, flags: shiftL)
        t.observeFlagsChanged(keyboardType: 40, flags: .maskAlternate)
        #expect(t.held.contains(.maskShift))
        #expect(t.held.contains(.maskAlternate))
        t.observeFlagsChanged(keyboardType: 92, flags: [])
        #expect(!t.held.contains(.maskShift))
        #expect(t.held.contains(.maskAlternate))
    }

    @Test func ignoresCapsLockAndFn() {
        var t = ModifierTracker()
        t.observeFlagsChanged(keyboardType: 92, flags: [.maskAlphaShift, .maskSecondaryFn])
        #expect(t.held.isEmpty)
    }

    @Test func resetDropsEverything() {
        var t = ModifierTracker()
        t.observeFlagsChanged(keyboardType: 92, flags: shiftL)
        t.reset()
        #expect(t.held.isEmpty)
    }
}

@Suite struct ParsingTests {
    @Test func hexParsing() {
        #expect(parseHexInt("0x1038") == 0x1038)
        #expect(parseHexInt("1038") == 0x1038)
        #expect(parseHexInt("#4152") == 4152)
        #expect(parseHexInt("zz") == nil)
    }
}

@Suite struct RepresentativeKeyCodeTests {
    @Test func noneHeld() {
        #expect(ModifierFlags.representativeKeyCode(for: []) == nil)
        #expect(ModifierFlags.representativeKeyCode(for: .maskAlphaShift) == nil)
    }

    @Test func leftAndRightShift() {
        let left = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | ModifierFlags.leftShift)
        let right = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | ModifierFlags.rightShift)
        #expect(ModifierFlags.representativeKeyCode(for: left) == 56)
        #expect(ModifierFlags.representativeKeyCode(for: right) == 60)
        #expect(ModifierFlags.representativeKeyCode(for: .maskShift) == 56)
    }

    @Test func priorityAndSides() {
        let rightOpt = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | ModifierFlags.rightOption)
        #expect(ModifierFlags.representativeKeyCode(for: rightOpt) == 61)
        #expect(ModifierFlags.representativeKeyCode(for: [.maskControl, .maskAlternate]) == 59)
        let rightCmd = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | ModifierFlags.rightCommand)
        #expect(ModifierFlags.representativeKeyCode(for: rightCmd) == 54)
    }
}
