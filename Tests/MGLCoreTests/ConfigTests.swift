import CoreGraphics
import Foundation
import Testing
@testable import MGLCore

@Suite struct ConfigTests {
    let wow = "com.blizzard.worldofwarcraft"

    @Test func exampleRoundTripsAndValidates() throws {
        let data = try MGLConfig.example.encoded()
        let decoded = try MGLConfig.decode(data)
        #expect(decoded == MGLConfig.example)
    }

    @Test func minimalProfileUsesDefaults() throws {
        let json = #"{"version":1,"profiles":[{"name":"Default"}]}"#
        let config = try MGLConfig.decode(Data(json.utf8))
        let s = PatchSettings(profile: config.profiles[0])
        #expect(s.modifierMask == ModifierName.mask(of: ModifierName.allCases))
        #expect(s.patchMouse)
        #expect(!s.syncGlobal)
        #expect(s.keyboardTypes == nil)
    }

    @Test func modifierAliases() throws {
        let json = #"{"version":1,"profiles":[{"name":"P","modifiers":["Shift","ctrl","alt","cmd"]}]}"#
        let config = try MGLConfig.decode(Data(json.utf8))
        #expect(config.profiles[0].modifiers == [.shift, .control, .option, .command])
    }

    @Test func unknownModifierIsRejected() {
        let json = #"{"version":1,"profiles":[{"name":"P","modifiers":["hyper"]}]}"#
        #expect(throws: ConfigError.self) { try MGLConfig.decode(Data(json.utf8)) }
    }

    @Test func invalidConfigsAreRejected() {
        let cases = [
            #"{"version":2,"profiles":[{"name":"P"}]}"#,
            #"{"version":1,"profiles":[]}"#,
            #"{"version":1,"profiles":[{"name":"P"},{"name":"p"}]}"#,
            #"{"version":1,"profiles":[{"name":"P","modifiers":[]}]}"#,
            #"{"version":1}"#,
        ]
        for json in cases {
            #expect(throws: ConfigError.self) { try MGLConfig.decode(Data(json.utf8)) }
        }
    }

    @Test func resolvesByBundleIDOrNameCaseInsensitive() {
        let c = MGLConfig.example
        #expect(c.resolve(bundleID: wow, appName: nil)?.name == "World of Warcraft")
        #expect(c.resolve(bundleID: "COM.BLIZZARD.WORLDOFWARCRAFT", appName: nil)?.name == "World of Warcraft")
        #expect(c.resolve(bundleID: "x.y", appName: "world of warcraft")?.name == "World of Warcraft")
    }

    @Test func disabledCatchAllMeansInactiveElsewhere() {
        #expect(MGLConfig.example.resolve(bundleID: "com.apple.finder", appName: "Finder") == nil)
    }

    @Test func enabledCatchAllIsFallbackButSpecificWins() {
        let c = MGLConfig(profiles: [
            Profile(name: "All", apps: []),
            Profile(name: "WoW", apps: [wow], modifiers: [.shift]),
        ])
        #expect(c.resolve(bundleID: wow, appName: nil)?.name == "WoW")
        #expect(c.resolve(bundleID: "com.apple.TextEdit", appName: "TextEdit")?.name == "All")
    }

    @Test func builtInDefaultAlwaysActive() {
        #expect(MGLConfig.builtInDefault.resolve(bundleID: nil, appName: nil)?.name == "Default")
    }

    @Test func overridesApply() {
        var o = PatchSettings.Overrides()
        o.keyboardTypes = [40]
        o.noMouse = true
        o.syncGlobal = true
        let s = PatchSettings(profile: Profile(name: "P", modifiers: [.shift])).applying(o)
        #expect(s.keyboardTypes == [40])
        #expect(!s.patchMouse)
        #expect(s.syncGlobal)
        #expect(s.modifierMask == ModifierName.shift.mask)
    }

    @Test func modifierMaskFiltersPatching() {
        var t = ModifierTracker()
        let shiftAndOpt = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | ModifierFlags.leftShift
            | CGEventFlags.maskAlternate.rawValue | ModifierFlags.leftOption)
        t.observeFlagsChanged(keyboardType: 92, flags: shiftAndOpt)
        let patched = t.patched([], mask: ModifierName.shift.mask)
        #expect(patched.contains(.maskShift))
        #expect(patched.rawValue & ModifierFlags.leftShift != 0)
        #expect(!patched.contains(.maskAlternate))
        #expect(patched.rawValue & ModifierFlags.leftOption == 0)
    }
}
