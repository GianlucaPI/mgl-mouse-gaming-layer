import CoreGraphics
import Foundation
import Testing
@testable import MGLCore

@Suite struct ScrollFixTests {
    let shiftL = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | ModifierFlags.leftShift | 0x100)
    let shiftBits = CGEventFlags.maskShift.rawValue | ModifierFlags.leftShift
    // Values seen on the Aerox 9 at the late stage (DEV_LOG): v=1/0.10/1px.
    let tickUp = ScrollAxes(delta1: 1, fixed1: 0.10, point1: 1)
    let tickDown = ScrollAxes(delta1: -1, fixed1: -0.10, point1: -1)
    let swapped = ScrollAxes(delta2: 1, fixed2: 1.0, point2: 10)

    @Test func detectsHorizontalOnly() {
        #expect(swapped.isHorizontalOnly)
        #expect(!tickUp.isHorizontalOnly)
        #expect(!ScrollAxes().isHorizontalOnly)
    }

    @Test func movesToVerticalKeepingSign() {
        #expect(swapped.movedToVertical() == ScrollAxes(delta1: 1, fixed1: 1.0, point1: 10))
        let down = ScrollAxes(delta2: -2, fixed2: -2.0, point2: -20).movedToVertical()
        #expect(down.delta1 == -2 && down.fixed1 == -2.0 && down.point1 == -20)
    }

    @Test func normalizeMakesEachNotchOneLine() {
        #expect(tickUp.normalized().fixed1 == 1.0)
        #expect(tickDown.normalized().fixed1 == -1.0)
        let accelerated = ScrollAxes(delta1: 3, fixed1: 4.5, point1: 45)
        #expect(accelerated.normalized() == accelerated)   // bigger values kept
        #expect(ScrollAxes().normalized() == ScrollAxes())
    }

    @Test func minimumPoints() {
        #expect(tickUp.withMinimumPoints(perLine: 10).point1 == 10)
        #expect(tickDown.withMinimumPoints(perLine: 10).point1 == -10)
        #expect(ScrollAxes(delta1: 1, point1: 25).withMinimumPoints(perLine: 10).point1 == 25)
    }

    @Test func keepShiftMarksPreciseKeepsShiftAndVertical() {
        let r = WheelFix.apply(axes: tickUp, flags: shiftL, shiftHeld: true, heldShiftBits: shiftBits,
                               mode: .verticalKeepShift, normalize: true)
        #expect(r.markContinuous)
        #expect(r.flags.contains(.maskShift))
        #expect(r.axes.delta1 == 1 && r.axes.fixed1 == 1.0 && r.axes.point1 == 10)
        #expect(r.axes.delta2 == 0)
    }

    @Test func keepShiftRestoresMissingShift() {
        let r = WheelFix.apply(axes: tickUp, flags: CGEventFlags(rawValue: 0x100), shiftHeld: true,
                               heldShiftBits: 0, mode: .verticalKeepShift, normalize: false)
        #expect(r.flags.contains(.maskShift))
        #expect(r.flags.rawValue & ModifierFlags.leftShift != 0)
    }

    @Test func keepShiftAlsoUnswapsHorizontal() {
        let r = WheelFix.apply(axes: swapped, flags: shiftL, shiftHeld: true, heldShiftBits: shiftBits,
                               mode: .verticalKeepShift, normalize: false)
        #expect(r.axes.delta1 == 1 && r.axes.delta2 == 0)
    }

    @Test func verticalStripsShiftOnlyAndIsNotPrecise() {
        let flags = CGEventFlags(rawValue: shiftL.rawValue | CGEventFlags.maskControl.rawValue | ModifierFlags.leftControl)
        let r = WheelFix.apply(axes: tickUp, flags: flags, shiftHeld: true, heldShiftBits: shiftBits,
                               mode: .vertical, normalize: false)
        #expect(!r.markContinuous)
        #expect(!r.flags.contains(.maskShift))
        #expect(r.flags.rawValue & (ModifierFlags.leftShift | ModifierFlags.rightShift) == 0)
        #expect(r.flags.contains(.maskControl))
        #expect(r.flags.rawValue & 0x100 != 0)
        #expect(r.axes == tickUp)
    }

    @Test func withoutShiftOnlyNormalizes() {
        let r = WheelFix.apply(axes: tickUp, flags: [], shiftHeld: false, heldShiftBits: 0,
                               mode: .verticalKeepShift, normalize: true)
        #expect(!r.markContinuous)
        #expect(r.flags == [])
        #expect(r.axes == ScrollAxes(delta1: 1, fixed1: 1.0, point1: 1))
    }

    @Test func systemModeAndNoNormalizeIsNoOp() {
        let r = WheelFix.apply(axes: swapped, flags: shiftL, shiftHeld: true, heldShiftBits: shiftBits,
                               mode: .system, normalize: false)
        #expect(r == WheelFix.Result(axes: swapped, flags: shiftL, markContinuous: false))
    }

    @Test func configParsesWheelOptions() throws {
        let json = #"{"version":1,"profiles":[{"name":"P","shiftScroll":"vertical-keep-shift","normalizeWheel":true}]}"#
        let c = try MGLConfig.decode(Data(json.utf8))
        let s = PatchSettings(profile: c.profiles[0])
        #expect(s.shiftScroll == .verticalKeepShift)
        #expect(s.normalizeWheel)
        let d = PatchSettings(profile: Profile(name: "D"))
        #expect(d.shiftScroll == .system && !d.normalizeWheel)
        #expect(MGLConfig.example.profiles[0].shiftScroll == .verticalKeepShift)
        #expect(MGLConfig.example.profiles[0].normalizeWheel == true)
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
