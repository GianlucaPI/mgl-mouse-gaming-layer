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

@Suite struct ParsingTests {
    @Test func hexParsing() {
        #expect(parseHexInt("0x1038") == 0x1038)
        #expect(parseHexInt("1038") == 0x1038)
        #expect(parseHexInt("#4152") == 4152)
        #expect(parseHexInt("zz") == nil)
    }
}
