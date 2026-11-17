import CoreGraphics
import Foundation
import Testing
@testable import MGLCore

@Suite struct ScrollFixTests {
    let shiftL = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | ModifierFlags.leftShift | 0x100)
    // A Shift-converted wheel-up tick: everything on the horizontal axis.
    let swapped = ScrollAxes(delta1: 0, delta2: 1, fixed1: 0, fixed2: 1.0, point1: 0, point2: 10)

    @Test func detectsHorizontalOnly() {
        #expect(swapped.isHorizontalOnly)
        #expect(!ScrollAxes(delta1: 1, fixed1: 1, point1: 10).isHorizontalOnly)
        #expect(!ScrollAxes().isHorizontalOnly)
    }

    @Test func movesToVerticalKeepingSign() {
        let v = swapped.movedToVertical()
        #expect(v == ScrollAxes(delta1: 1, delta2: 0, fixed1: 1.0, fixed2: 0, point1: 10, point2: 0))
        let down = ScrollAxes(delta2: -2, fixed2: -2.0, point2: -20).movedToVertical()
        #expect(down.delta1 == -2 && down.fixed1 == -2.0 && down.point1 == -20)
    }

    @Test func verticalModeUnswapsAndStripsShiftOnly() {
        let flags = CGEventFlags(rawValue: shiftL.rawValue | CGEventFlags.maskControl.rawValue | ModifierFlags.leftControl)
        let r = ShiftScroll.fix(axes: swapped, flags: flags, mode: .vertical)
        #expect(r.axes.delta1 == 1 && r.axes.delta2 == 0)
        #expect(!r.flags.contains(.maskShift))
        #expect(r.flags.rawValue & (ModifierFlags.leftShift | ModifierFlags.rightShift) == 0)
        #expect(r.flags.contains(.maskControl))          // other modifiers kept
        #expect(r.flags.rawValue & 0x100 != 0)            // non-modifier bits kept
    }

    @Test func keepShiftModeOnlyUnswaps() {
        let r = ShiftScroll.fix(axes: swapped, flags: shiftL, mode: .verticalKeepShift)
        #expect(r.axes.delta1 == 1)
        #expect(r.flags == shiftL)
    }

    @Test func alreadyVerticalIsNotTouchedButShiftStripped() {
        let vertical = ScrollAxes(delta1: 1, fixed1: 1, point1: 10)
        let r = ShiftScroll.fix(axes: vertical, flags: shiftL, mode: .vertical)
        #expect(r.axes == vertical)
        #expect(!r.flags.contains(.maskShift))
    }

    @Test func systemModeIsNoOp() {
        let r = ShiftScroll.fix(axes: swapped, flags: shiftL, mode: .system)
        #expect(r.axes == swapped && r.flags == shiftL)
    }

    @Test func configParsesShiftScroll() throws {
        let json = #"{"version":1,"profiles":[{"name":"P","shiftScroll":"vertical-keep-shift"}]}"#
        let c = try MGLConfig.decode(Data(json.utf8))
        #expect(PatchSettings(profile: c.profiles[0]).shiftScroll == .verticalKeepShift)
        #expect(PatchSettings(profile: Profile(name: "D")).shiftScroll == .system)
        #expect(MGLConfig.example.profiles[0].shiftScroll == .verticalKeepShift)
        let bad = #"{"version":1,"profiles":[{"name":"P","shiftScroll":"sideways"}]}"#
        #expect(throws: ConfigError.self) { try MGLConfig.decode(Data(bad.utf8)) }
    }

    @Test func tolerantShiftScrollNames() {
        #expect(ShiftScrollMode(name: "Vertical-Keep-Shift") == .verticalKeepShift)
        #expect(ShiftScrollMode(name: " vertical_keep_shift ") == .verticalKeepShift)
        #expect(ShiftScrollMode(name: "vertical keep shift") == .verticalKeepShift)
        #expect(ShiftScrollMode(name: "vertical\u{2013}keep\u{2013}shift") == .verticalKeepShift)
        #expect(ShiftScrollMode(name: "verticavertical-keep-shift") == nil)
    }

    @Test func errorNamesTheBadValueAndTheValidOnes() {
        let bad = #"{"version":1,"profiles":[{"name":"P","shiftScroll":"verticavertical-keep-shift"}]}"#
        do {
            _ = try MGLConfig.decode(Data(bad.utf8))
            Issue.record("expected an error")
        } catch {
            let text = "\(error)"
            #expect(text.contains("profiles[0].shiftScroll"))
            #expect(text.contains("verticavertical-keep-shift"))
            #expect(text.contains("vertical-keep-shift"))
        }
    }
}
