import CoreGraphics
import Foundation

/// How MGL treats wheel scrolling while Shift is held.
///
/// AppKit (inside the app, after every event tap) turns Shift + vertical wheel from
/// non-precise devices into a *horizontal* scroll and keeps Shift, so games never see
/// "Shift + wheel up/down" (WoW's SHIFT-MOUSEWHEELUP / DOWN). Verified with
/// `mgl-probe --late`: at the last tap stage the tick is still vertical with Shift.
public enum ShiftScrollMode: String, Codable, CaseIterable {
    /// Leave it to macOS (horizontal scroll). Right for browsers, editors, Finder.
    case system
    /// Remove Shift from the scroll event (vertical axis), so AppKit does not convert it.
    /// Only for games that track Shift themselves (NOT WoW: it then sees a plain wheel).
    case vertical
    /// Keep Shift and the vertical axis, presenting the tick as a precise (pixel) scroll so
    /// AppKit does not convert it. For games that read modifiers from the event (WoW).
    case verticalKeepShift = "vertical-keep-shift"

    /// Tolerant: case, surrounding spaces, "_" / " " / typographic dashes all accepted.
    public init?(name: String) {
        guard let mode = ShiftScrollMode(rawValue: ConfigText.normalized(name)) else { return nil }
        self = mode
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let mode = ShiftScrollMode(name: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown value \"\(raw)\" (use "
                    + Self.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ") + ")"))
        }
        self = mode
    }
}

/// Normalization for enum-like config strings typed by hand.
public enum ConfigText {
    public static func normalized(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for dash in ["_", " ", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}"] {
            s = s.replacingOccurrences(of: dash, with: "-")
        }
        return s
    }
}

/// The delta fields of a scroll-wheel event (axis 1 = vertical, axis 2 = horizontal).
public struct ScrollAxes: Equatable {
    public var delta1: Int64, delta2: Int64      // line deltas
    public var fixed1: Double, fixed2: Double    // fixed-point line deltas
    public var point1: Int64, point2: Int64      // pixel deltas

    public init(delta1: Int64 = 0, delta2: Int64 = 0, fixed1: Double = 0, fixed2: Double = 0,
                point1: Int64 = 0, point2: Int64 = 0) {
        self.delta1 = delta1; self.delta2 = delta2
        self.fixed1 = fixed1; self.fixed2 = fixed2
        self.point1 = point1; self.point2 = point2
    }

    public init(event: CGEvent) {
        delta1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        delta2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        fixed1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        fixed2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        point1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        point2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    }

    public func write(to event: CGEvent) {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: delta1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: delta2)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed2)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: point1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: point2)
    }

    /// Vertical part empty, horizontal part set: what a Shift-converted wheel tick looks like.
    public var isHorizontalOnly: Bool {
        delta1 == 0 && fixed1 == 0 && point1 == 0 && (delta2 != 0 || fixed2 != 0 || point2 != 0)
    }

    /// Moves the horizontal deltas to the vertical axis (same sign).
    public func movedToVertical() -> ScrollAxes {
        ScrollAxes(delta1: delta2, delta2: 0, fixed1: fixed2, fixed2: 0, point1: point2, point2: 0)
    }

    public var summary: String {
        "v=\(delta1)/\(String(format: "%.2f", fixed1))/\(point1)px h=\(delta2)/\(String(format: "%.2f", fixed2))/\(point2)px"
    }
}

public enum WheelFix {
    /// Pixels per line used when a wheel tick is presented as a precise (pixel) scroll.
    public static let pixelsPerLine: Int64 = 10

    public struct Result: Equatable {
        public var axes: ScrollAxes
        public var flags: CGEventFlags
        /// Present the tick as a precise (continuous) scroll, so AppKit does not turn
        /// Shift + wheel into horizontal scrolling.
        public var markContinuous: Bool
    }

    /// Fix for one notched-wheel (non-continuous) scroll event, as seen at the last tap
    /// stage before apps. Pure function.
    /// - Parameters:
    ///   - shiftHeld: Shift is physically held (tracker) or present in the event.
    ///   - heldShiftBits: Shift bits (incl. left/right) to put back when keeping Shift.
    ///   - normalize: make every notch worth at least one whole line (fixed-point delta),
    ///     so games that accumulate `deltaY` react on the first notch.
    public static func apply(axes: ScrollAxes, flags: CGEventFlags, shiftHeld: Bool, heldShiftBits: UInt64,
                             mode: ShiftScrollMode, normalize: Bool) -> Result {
        var a = normalize ? axes.normalized() : axes
        var f = flags
        var continuous = false
        if shiftHeld && mode != .system {
            if a.isHorizontalOnly { a = a.movedToVertical() }
            switch mode {
            case .vertical:
                f = CGEventFlags(rawValue: f.rawValue & ~ModifierName.shift.mask)
            case .verticalKeepShift:
                let bits = heldShiftBits != 0 ? heldShiftBits : CGEventFlags.maskShift.rawValue | ModifierFlags.leftShift
                f = CGEventFlags(rawValue: f.rawValue | bits)
                continuous = true
                a = a.withMinimumPoints(perLine: pixelsPerLine)
            case .system:
                break
            }
        }
        return Result(axes: a, flags: f, markContinuous: continuous)
    }
}

extension ScrollAxes {
    /// Each axis with a non-zero line delta gets a fixed-point delta of at least that many
    /// lines (macOS can report e.g. 0.1 per notch). Larger (accelerated) values are kept.
    public func normalized() -> ScrollAxes {
        func fix(_ delta: Int64, _ fixed: Double) -> Double {
            guard delta != 0, abs(fixed) < Double(abs(delta)) else { return fixed }
            return Double(delta)
        }
        var a = self
        a.fixed1 = fix(delta1, fixed1)
        a.fixed2 = fix(delta2, fixed2)
        return a
    }

    /// Pixel deltas of at least `perLine` px per line (precise scrolls are read in pixels).
    public func withMinimumPoints(perLine: Int64) -> ScrollAxes {
        func fix(_ delta: Int64, _ point: Int64) -> Int64 {
            let want = delta * perLine
            return abs(point) < abs(want) ? want : point
        }
        var a = self
        a.point1 = fix(delta1, point1)
        a.point2 = fix(delta2, point2)
        return a
    }
}
