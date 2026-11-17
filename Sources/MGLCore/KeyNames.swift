/// Name tables for HID keyboard usages (page 0x07) and macOS virtual keycodes.
public enum KeyNames {
    public static func hidUsage(page: Int, usage: Int) -> String {
        switch page {
        case 0x07: return hidKeyboardUsage(usage)
        case 0x09: return "Button\(usage)"
        case 0x0C: return "Consumer \(hex(usage, width: 2))"
        default: return "page \(hex(page, width: 2)) usage \(hex(usage, width: 2))"
        }
    }

    public static func hidKeyboardUsage(_ usage: Int) -> String {
        switch usage {
        case 0x04...0x1D:
            return String(UnicodeScalar(UInt8(ascii: "A") + UInt8(usage - 0x04)))
        case 0x1E...0x26:
            return String(usage - 0x1E + 1)
        case 0x27: return "0"
        case 0x3A...0x45: return "F\(usage - 0x3A + 1)"
        case 0x68...0x73: return "F\(usage - 0x68 + 13)"
        case 0x59...0x61: return "Keypad\(usage - 0x59 + 1)"
        default: return hidKeyboardSpecial[usage] ?? "usage \(hex(usage, width: 2))"
        }
    }

    private static let hidKeyboardSpecial: [Int: String] = [
        0x28: "Return", 0x29: "Escape", 0x2A: "Backspace", 0x2B: "Tab", 0x2C: "Space",
        0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]", 0x31: "\\", 0x32: "#(non-US)",
        0x33: ";", 0x34: "'", 0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/", 0x39: "CapsLock",
        0x46: "PrintScreen", 0x47: "ScrollLock", 0x48: "Pause", 0x49: "Insert",
        0x4A: "Home", 0x4B: "PageUp", 0x4C: "Delete", 0x4D: "End", 0x4E: "PageDown",
        0x4F: "Right", 0x50: "Left", 0x51: "Down", 0x52: "Up", 0x53: "NumLock",
        0x54: "Keypad/", 0x55: "Keypad*", 0x56: "Keypad-", 0x57: "Keypad+", 0x58: "KeypadEnter",
        0x62: "Keypad0", 0x63: "Keypad.", 0x64: "<>(non-US)", 0x67: "Keypad=",
        0xE0: "LeftCtrl", 0xE1: "LeftShift", 0xE2: "LeftAlt/Opt", 0xE3: "LeftGUI/Cmd",
        0xE4: "RightCtrl", 0xE5: "RightShift", 0xE6: "RightAlt/Opt", 0xE7: "RightGUI/Cmd",
    ]

    /// Is this a real key usage (excludes rollover/error codes 0x00-0x03 and reserved ranges)?
    public static func isRealKeyboardUsage(_ usage: Int) -> Bool {
        (0x04...0xA4).contains(usage) || (0xE0...0xE7).contains(usage)
    }

    public static func isModifierUsage(_ usage: Int) -> Bool {
        (0xE0...0xE7).contains(usage)
    }

    /// macOS virtual keycodes (Carbon kVK_* values, ANSI layout).
    public static func macKeyCode(_ code: Int) -> String {
        macKeyCodes[code] ?? "kc\(code)"
    }

    private static let macKeyCodes: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Backspace",
        53: "Escape", 54: "RightCmd", 55: "LeftCmd", 56: "LeftShift", 57: "CapsLock",
        58: "LeftOpt", 59: "LeftCtrl", 60: "RightShift", 61: "RightOpt", 62: "RightCtrl",
        63: "Fn", 64: "F17", 65: "Keypad.", 67: "Keypad*", 69: "Keypad+", 71: "KeypadClear",
        75: "Keypad/", 76: "KeypadEnter", 78: "Keypad-", 79: "F18", 80: "F19", 81: "Keypad=",
        82: "Keypad0", 83: "Keypad1", 84: "Keypad2", 85: "Keypad3", 86: "Keypad4",
        87: "Keypad5", 88: "Keypad6", 89: "Keypad7", 90: "F20", 91: "Keypad8", 92: "Keypad9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help/Insert", 115: "Home", 116: "PageUp", 117: "ForwardDelete", 118: "F4",
        119: "End", 120: "F2", 121: "PageDown", 122: "F1", 123: "Left", 124: "Right",
        125: "Down", 126: "Up",
    ]
}
