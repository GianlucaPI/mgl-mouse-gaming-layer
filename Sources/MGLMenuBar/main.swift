import AppKit
import MGLCore
import ServiceManagement

// MGL menu-bar app (Phase 5). Same engine as the `mgl` CLI, plus:
// status icon, pause, profile override, config editing, launch at login.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum DefaultsKey {
        static let enabled = "enabled"
        static let forcedProfile = "forcedProfile"
    }

    private var statusItem: NSStatusItem!
    private let engine = MGLEngine()
    private var started = false
    private var startError: String?
    private var permissionTimer: Timer?
    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        engine.enabled = defaults.object(forKey: DefaultsKey.enabled) as? Bool ?? true
        engine.forcedProfile = defaults.string(forKey: DefaultsKey.forcedProfile)
        engine.onEvent = { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
        refreshIcon()
        startIfPermitted(prompt: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // MARK: Startup & permission

    /// The event tap needs Accessibility. Until it is granted, poll every 2 s.
    private func startIfPermitted(prompt: Bool) {
        guard !started else { return }
        guard Permissions.accessibilityGranted else {
            if prompt { _ = Permissions.requestAccessibility() }
            if permissionTimer == nil {
                permissionTimer = Timer.scheduledTimer(timeInterval: 2, target: self,
                                                       selector: #selector(permissionTick), userInfo: nil, repeats: true)
            }
            refreshIcon()
            return
        }
        permissionTimer?.invalidate()
        permissionTimer = nil
        do {
            try engine.start()
            engine.watchConfigFile()
            started = true
            startError = nil
        } catch {
            startError = "\(error)"
        }
        refreshIcon()
    }

    @objc private func permissionTick() {
        startIfPermitted(prompt: false)
    }

    // MARK: Icon

    private func refreshIcon() {
        let symbol: String
        let tooltip: String
        let status = engine.status
        if !Permissions.accessibilityGranted && !started {
            symbol = "exclamationmark.triangle"
            tooltip = "MGL: Accessibility permission needed"
        } else if startError != nil || status.configError != nil {
            symbol = "exclamationmark.triangle"
            tooltip = "MGL: error — open the menu for details"
        } else if let settings = status.settings {
            symbol = "computermouse.fill"
            tooltip = "MGL: active — \(settings.profileName)"
        } else {
            symbol = "computermouse"
            tooltip = status.enabled ? "MGL: inactive in \(status.app.name ?? "this app")" : "MGL: paused"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !engine.enabled
        statusItem.button?.toolTip = tooltip
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = engine.status

        menu.addItem(disabledItem("MGL \(MGL.version)"))
        if !started {
            if !Permissions.accessibilityGranted {
                menu.addItem(disabledItem("⚠️ Accessibility permission needed"))
                menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibilitySettings)))
            } else if let startError {
                menu.addItem(disabledItem("⚠️ \(startError)"))
                menu.addItem(item("Retry", #selector(retryStart)))
            }
        } else if let settings = status.settings {
            menu.addItem(disabledItem("Active — \(settings.profileName)"))
        } else {
            menu.addItem(disabledItem(status.enabled ? "Inactive in \(status.app.name ?? "this app")" : "Paused"))
        }
        if let error = status.configError {
            menu.addItem(disabledItem("⚠️ Config error (previous config kept):"))
            menu.addItem(disabledItem("   " + String(error.prefix(80))))
        }
        menu.addItem(.separator())

        let enabledItem = item("Enabled", #selector(toggleEnabled), key: "e")
        enabledItem.state = engine.enabled ? .on : .off
        menu.addItem(enabledItem)

        let profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let profileMenu = NSMenu()
        let auto = item("Automatic (by frontmost app)", #selector(selectProfile(_:)))
        auto.representedObject = nil
        auto.state = engine.forcedProfile == nil ? .on : .off
        profileMenu.addItem(auto)
        profileMenu.addItem(.separator())
        for profile in engine.config?.profiles ?? [] {
            let p = item(profile.name + (profile.isEnabled ? "" : " (disabled)"), #selector(selectProfile(_:)))
            p.representedObject = profile.name
            p.state = engine.forcedProfile?.caseInsensitiveCompare(profile.name) == .orderedSame ? .on : .off
            profileMenu.addItem(p)
        }
        profileItem.submenu = profileMenu
        menu.addItem(profileItem)
        menu.addItem(.separator())

        menu.addItem(item(engine.configFromFile ? "Edit Config…" : "Create & Edit Config…", #selector(editConfig), key: ","))
        menu.addItem(item("Show Config in Finder", #selector(revealConfig)))
        menu.addItem(item("Reload Config", #selector(reloadConfig), key: "r"))
        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        switch SMAppService.mainApp.status {
        case .enabled: login.state = .on
        case .requiresApproval: login.state = .mixed
        default: login.state = .off
        }
        menu.addItem(login)
        menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibilitySettings)))
        menu.addItem(.separator())
        menu.addItem(item("Quit MGL", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        engine.enabled.toggle()
        defaults.set(engine.enabled, forKey: DefaultsKey.enabled)
        refreshIcon()
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        engine.forcedProfile = sender.representedObject as? String
        defaults.set(engine.forcedProfile, forKey: DefaultsKey.forcedProfile)
        refreshIcon()
    }

    @objc private func editConfig() {
        do {
            try engine.ensureConfigFile()
            engine.reloadConfig()
            // Open with the default editor for JSON, falling back to TextEdit.
            let url = engine.configURL
            if let app = NSWorkspace.shared.urlForApplication(toOpen: url) {
                NSWorkspace.shared.open([url], withApplicationAt: app,
                                        configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        } catch {
            alert("Cannot create the config file", "\(error)")
        }
    }

    @objc private func revealConfig() {
        try? engine.ensureConfigFile()
        NSWorkspace.shared.activateFileViewerSelecting([engine.configURL])
    }

    @objc private func reloadConfig() {
        engine.reloadConfig()
        refreshIcon()
    }

    @objc private func retryStart() {
        startIfPermitted(prompt: true)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            alert("Launch at Login failed",
                  "\(error.localizedDescription)\n\nMove MGL.app to /Applications (or ~/Applications) and try again.")
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

// Top-level code runs on the main thread.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu-bar only, no Dock icon (also LSUIElement in Info.plist)
    app.run()
}
