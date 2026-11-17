import ApplicationServices
import CoreGraphics
import IOKit.hid

/// Privacy permissions required by MGL.
/// Note: when run from a terminal, macOS grants permissions to the *terminal app*
/// (Terminal, iTerm, ...), not to the binary itself.
public enum Permissions {
    /// Input Monitoring: needed to open HID keyboards and for listen-only event taps.
    public static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Triggers the system prompt (only shown once per app). Returns current status.
    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Accessibility: needed for *active* (modifying) event taps — Phase 2.
    public static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    public static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static func report() -> String {
        """
        Input Monitoring: \(inputMonitoringGranted ? "granted" : "NOT granted")
        Accessibility:    \(accessibilityGranted ? "granted" : "NOT granted")
        """
    }
}
