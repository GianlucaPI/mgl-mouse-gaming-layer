import CoreGraphics
import Foundation

/// A modifier MGL can propagate. Accepts aliases when decoding ("ctrl", "alt", "opt", "cmd").
public enum ModifierName: String, Codable, CaseIterable {
    case shift, control, option, command

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = ModifierName(name: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown modifier \"\(raw)\" (use shift, control, option, command)"))
        }
        self = value
    }

    public init?(name: String) {
        switch ConfigText.normalized(name) {
        case "shift": self = .shift
        case "control", "ctrl": self = .control
        case "option", "opt", "alt": self = .option
        case "command", "cmd": self = .command
        default: return nil
        }
    }

    /// Device-independent bit plus both side-specific bits.
    public var mask: UInt64 {
        switch self {
        case .shift: return CGEventFlags.maskShift.rawValue | ModifierFlags.leftShift | ModifierFlags.rightShift
        case .control: return CGEventFlags.maskControl.rawValue | ModifierFlags.leftControl | ModifierFlags.rightControl
        case .option: return CGEventFlags.maskAlternate.rawValue | ModifierFlags.leftOption | ModifierFlags.rightOption
        case .command: return CGEventFlags.maskCommand.rawValue | ModifierFlags.leftCommand | ModifierFlags.rightCommand
        }
    }

    public static func mask(of names: [ModifierName]) -> UInt64 {
        names.reduce(0) { $0 | $1.mask }
    }
}

/// One profile: when it applies (apps) and how MGL behaves while it is active.
public struct Profile: Codable, Equatable {
    public var name: String
    /// Disabled profiles are skipped during resolution. Default: true.
    public var enabled: Bool?
    /// Bundle IDs or app names (case-insensitive). Empty or missing = any app (catch-all).
    public var apps: [String]?
    /// Modifiers to propagate. Default: all four.
    public var modifiers: [ModifierName]?
    /// Only patch key events from these keyboardTypes (e.g. [40] for the Aerox 9 over BLE).
    /// Missing = any key event missing a held modifier.
    public var keyboardTypes: [Int]?
    /// Patch mouse clicks / scroll. Default: true.
    public var patchMouse: Bool?
    /// Restore macOS's global modifier state after a patched key. Default: false.
    public var syncGlobal: Bool?
    /// Shift + mouse wheel handling (see ShiftScrollMode). Default: "system".
    public var shiftScroll: ShiftScrollMode?

    public init(name: String, enabled: Bool? = nil, apps: [String]? = nil, modifiers: [ModifierName]? = nil,
                keyboardTypes: [Int]? = nil, patchMouse: Bool? = nil, syncGlobal: Bool? = nil,
                shiftScroll: ShiftScrollMode? = nil) {
        self.name = name
        self.enabled = enabled
        self.apps = apps
        self.modifiers = modifiers
        self.keyboardTypes = keyboardTypes
        self.patchMouse = patchMouse
        self.syncGlobal = syncGlobal
        self.shiftScroll = shiftScroll
    }

    public var isEnabled: Bool { enabled ?? true }
    public var isCatchAll: Bool { apps?.isEmpty ?? true }

    public func matches(bundleID: String?, appName: String?) -> Bool {
        guard let apps, !apps.isEmpty else { return true }
        return apps.contains { entry in
            (bundleID.map { entry.caseInsensitiveCompare($0) == .orderedSame } ?? false)
                || (appName.map { entry.caseInsensitiveCompare($0) == .orderedSame } ?? false)
        }
    }
}

public struct MGLConfig: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    /// Ordered by priority: the first enabled profile listing the frontmost app wins;
    /// otherwise the first enabled catch-all profile; otherwise MGL is inactive.
    public var profiles: [Profile]

    public init(version: Int = MGLConfig.currentVersion, profiles: [Profile]) {
        self.version = version
        self.profiles = profiles
    }

    /// Used when no config file exists: always active, everything on (Phase 2 behavior).
    public static let builtInDefault = MGLConfig(profiles: [Profile(name: "Default")])

    /// Written by `mgl config init`: active only in World of Warcraft.
    public static let example = MGLConfig(profiles: [
        Profile(
            name: "World of Warcraft",
            enabled: true,
            // Bundle ID verified on macOS (2026-11-17); the app's display name is "Wow".
            apps: ["com.blizzard.worldofwarcraft", "Wow", "World of Warcraft"],
            modifiers: ModifierName.allCases,
            patchMouse: true,
            syncGlobal: false,
            shiftScroll: .verticalKeepShift
        ),
        Profile(
            name: "Everywhere else",
            enabled: false,
            apps: [],
            modifiers: ModifierName.allCases,
            patchMouse: true,
            syncGlobal: false,
            shiftScroll: .system
        ),
    ])

    // MARK: Resolution

    public func resolve(bundleID: String?, appName: String?) -> Profile? {
        let enabled = profiles.filter(\.isEnabled)
        return enabled.first { !$0.isCatchAll && $0.matches(bundleID: bundleID, appName: appName) }
            ?? enabled.first(where: \.isCatchAll)
    }

    public func profile(named name: String) -> Profile? {
        profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Validation

    public func validate() throws {
        guard version == Self.currentVersion else {
            throw ConfigError.invalid("unsupported version \(version) (expected \(Self.currentVersion))")
        }
        guard !profiles.isEmpty else { throw ConfigError.invalid("no profiles defined") }
        var seen = Set<String>()
        for p in profiles {
            let key = p.name.lowercased()
            guard !key.isEmpty else { throw ConfigError.invalid("a profile has an empty name") }
            guard seen.insert(key).inserted else { throw ConfigError.invalid("duplicate profile name \"\(p.name)\"") }
            if let m = p.modifiers, m.isEmpty {
                throw ConfigError.invalid("profile \"\(p.name)\" has an empty modifiers list")
            }
        }
    }

    // MARK: Files

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MGL/config.json")
    }

    public static func decode(_ data: Data) throws -> MGLConfig {
        let config: MGLConfig
        do { config = try JSONDecoder().decode(MGLConfig.self, from: data) } catch {
            throw ConfigError.invalid(Self.describe(error))
        }
        try config.validate()
        return config
    }

    public static func load(from url: URL) throws -> MGLConfig {
        try decode(try Data(contentsOf: url))
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return "\(error)" }
        func path(_ c: DecodingError.Context) -> String {
            c.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        }
        func at(_ c: DecodingError.Context) -> String {
            let p = path(c)
            return p.isEmpty ? "" : p + ": "
        }
        switch error {
        case .dataCorrupted(let c): return "\(at(c))\(c.debugDescription)"
        case .keyNotFound(let key, let c): return "\(at(c))missing key \"\(key.stringValue)\""
        case .typeMismatch(_, let c), .valueNotFound(_, let c): return "\(at(c))\(c.debugDescription)"
        @unknown default: return "\(error)"
        }
    }
}

public enum ConfigError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self { case .invalid(let msg): return "Invalid config: \(msg)" }
    }
}

/// The runtime settings of the patcher, derived from a profile plus CLI overrides.
public struct PatchSettings: Equatable {
    public var profileName: String
    public var modifierMask: UInt64
    public var keyboardTypes: Set<Int>?
    public var patchMouse: Bool
    public var syncGlobal: Bool
    public var shiftScroll: ShiftScrollMode

    public init(profile: Profile) {
        profileName = profile.name
        modifierMask = ModifierName.mask(of: profile.modifiers ?? ModifierName.allCases)
        keyboardTypes = profile.keyboardTypes.map(Set.init)
        patchMouse = profile.patchMouse ?? true
        syncGlobal = profile.syncGlobal ?? false
        shiftScroll = profile.shiftScroll ?? .system
    }

    /// Command-line overrides applied on top of every profile.
    public struct Overrides {
        public var keyboardTypes: Set<Int>?
        public var noMouse = false
        public var syncGlobal = false
        public init() {}
    }

    public func applying(_ o: Overrides) -> PatchSettings {
        var s = self
        if let k = o.keyboardTypes { s.keyboardTypes = k }
        if o.noMouse { s.patchMouse = false }
        if o.syncGlobal { s.syncGlobal = true }
        return s
    }
}
