import CoreGraphics

/// How MGL treats wheel scrolling while Shift is held.
///
/// macOS turns Shift + vertical wheel (non-continuous mice) into a *horizontal* scroll and
/// keeps Shift in the flags, so games never see "Shift + wheel up/down" (WoW's
/// SHIFT-MOUSEWHEELUP / DOWN). Games track Shift themselves from flagsChanged events.
public enum ShiftScrollMode: String, Codable, CaseIterable {
    /// Leave it to macOS (horizontal scroll). Right for browsers, editors, Finder.
    case system
    /// Undo the axis swap and remove Shift from the scroll event, so nothing downstream
    /// converts it again. The game still knows Shift is held. Recommended for games.
    case vertical
    /// Undo the axis swap but keep Shift in the event flags (fallback if a game needs it).
    case verticalKeepShift = "vertical-keep-shift"
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

public enum ShiftScroll {
    /// Computes the fixed axes and flags for a non-continuous wheel event while Shift is held.
    /// `flags` must already include the held modifiers MGL wants to add.
    public static func fix(axes: ScrollAxes, flags: CGEventFlags, mode: ShiftScrollMode)
        -> (axes: ScrollAxes, flags: CGEventFlags)
    {
        guard mode != .system else { return (axes, flags) }
        let newAxes = axes.isHorizontalOnly ? axes.movedToVertical() : axes
        var newFlags = flags
        if mode == .vertical {
            newFlags = CGEventFlags(rawValue: flags.rawValue & ~ModifierName.shift.mask)
        }
        return (newAxes, newFlags)
    }
}
