import AppKit

/// Reports the frontmost application now and whenever it changes.
/// Needs a running main run loop (CFRunLoopRun / RunLoop.main); no permission required.
public final class FrontmostAppMonitor {
    public struct AppInfo: Equatable {
        public let bundleID: String?
        public let name: String?
        public let pid: Int32

        public var label: String { "\(name ?? "?") (\(bundleID ?? "no bundle id"))" }

        init(_ app: NSRunningApplication?) {
            bundleID = app?.bundleIdentifier
            name = app?.localizedName
            pid = app?.processIdentifier ?? 0
        }
    }

    private let onChange: (AppInfo) -> Void
    private var observer: NSObjectProtocol?

    public init(onChange: @escaping (AppInfo) -> Void) {
        self.onChange = onChange
    }

    public static var current: AppInfo { AppInfo(NSWorkspace.shared.frontmostApplication) }

    /// Calls `onChange` immediately with the current app, then on every activation.
    public func start() {
        onChange(Self.current)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.onChange(AppInfo(app))
        }
    }

    public func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}
