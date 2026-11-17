import Foundation

/// Everything the CLI and the menu-bar app share: config loading/reloading, the
/// frontmost-app → profile resolution, pause/forced profile, and the event tap.
/// Main-thread only.
public final class MGLEngine {
    public struct Status: Equatable {
        public var enabled: Bool
        /// Effective settings; nil = inactive (paused, no matching profile or no valid config).
        public var settings: PatchSettings?
        public var app: FrontmostAppMonitor.AppInfo
        public var forcedProfile: String?
        public var configFromFile: Bool
        public var configError: String?
    }

    public enum Event {
        case statusChanged(Status)
        case configReloaded
        case configReloadFailed(String)
    }

    public let configURL: URL
    public let patcher: ModifierPatcher
    public var onEvent: ((Event) -> Void)?

    public private(set) var config: MGLConfig?
    public private(set) var configFromFile = false
    public private(set) var configError: String?

    /// false = paused: everything passes through.
    public var enabled = true { didSet { apply() } }
    /// Use this profile regardless of the frontmost app (nil = automatic).
    public var forcedProfile: String? { didSet { apply() } }
    public var overrides: PatchSettings.Overrides { didSet { apply() } }

    private var currentApp = FrontmostAppMonitor.current
    private var appMonitor: FrontmostAppMonitor?
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var lastConfigData: Data?
    private var reloadWorkItem: DispatchWorkItem?
    private var lastStatus: Status?

    public init(configURL: URL = MGLConfig.defaultURL, dryRun: Bool = false,
                overrides: PatchSettings.Overrides = .init(),
                onActivity: @escaping (ModifierPatcher.Activity) -> Void = { _ in }) {
        self.configURL = configURL
        self.overrides = overrides
        self.patcher = ModifierPatcher(settings: nil, dryRun: dryRun, onActivity: onActivity)
    }

    // MARK: Config

    /// Missing file = built-in default (always active).
    public static func loadConfig(at url: URL) throws -> (config: MGLConfig, fromFile: Bool, data: Data?) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (MGLConfig.builtInDefault, false, nil)
        }
        let data = try Data(contentsOf: url)
        return (try MGLConfig.decode(data), true, data)
    }

    /// Reloads the config. On error the previous valid config stays in use.
    @discardableResult
    public func reloadConfig() -> Bool {
        do {
            let loaded = try Self.loadConfig(at: configURL)
            config = loaded.config
            configFromFile = loaded.fromFile
            lastConfigData = loaded.data
            configError = nil
            if let forced = forcedProfile, loaded.config.profile(named: forced) == nil { forcedProfile = nil }
            onEvent?(.configReloaded)
            apply()
            return true
        } catch {
            configError = "\(error)"
            onEvent?(.configReloadFailed(configError!))
            apply()
            return false
        }
    }

    /// Creates the config file from the example if it does not exist yet.
    public func ensureConfigFile() throws {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        try MGLConfig.example.write(to: configURL)
    }

    /// Reloads automatically when the config file changes. Watches the directory (editors
    /// usually save by replacing the file) and the file itself (in-place writes); the file
    /// watcher is re-armed after every change. Debounced; ignores no-op writes.
    public func watchConfigFile() {
        guard dirWatcher == nil else { return }
        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dirWatcher = makeWatcher(path: dir.path)
        armFileWatcher()
    }

    private func armFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = makeWatcher(path: configURL.path)
    }

    private func makeWatcher(path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReloadIfChanged() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func scheduleReloadIfChanged() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.armFileWatcher()  // the file may have been replaced, created or deleted
            let data = try? Data(contentsOf: self.configURL)
            guard data != self.lastConfigData else { return }
            self.reloadConfig()
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // MARK: Lifecycle

    /// Loads the config (invalid config → inactive, see `configError`), starts the tap
    /// and the frontmost-app monitor. Throws if the event tap cannot be created.
    public func start() throws {
        if config == nil && configError == nil { reloadConfig() }
        try patcher.start()
        let monitor = FrontmostAppMonitor { [weak self] app in
            self?.currentApp = app
            self?.apply()
        }
        appMonitor = monitor
        monitor.start()
        apply(forceNotify: true)
    }

    public func stop() {
        patcher.stop()
        appMonitor?.stop()
        appMonitor = nil
        dirWatcher?.cancel()
        dirWatcher = nil
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    // MARK: State

    public var status: Status {
        Status(enabled: enabled, settings: patcher.settings, app: currentApp, forcedProfile: forcedProfile,
               configFromFile: configFromFile, configError: configError)
    }

    private func resolvedSettings() -> PatchSettings? {
        guard enabled, let config else { return nil }
        let profile = forcedProfile.flatMap(config.profile(named:))
            ?? config.resolve(bundleID: currentApp.bundleID, appName: currentApp.name)
        return profile.map { PatchSettings(profile: $0).applying(overrides) }
    }

    private func apply(forceNotify: Bool = false) {
        patcher.settings = resolvedSettings()
        let status = self.status
        guard forceNotify || status != lastStatus else { return }
        lastStatus = status
        onEvent?(.statusChanged(status))
    }
}
