import AgentAvatarCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: AvatarWindowController?
    private var settingsController: SettingsWindowController?
    private var coordinator: AvatarStateCoordinator?
    private var server: LocalHTTPServer?
    private var library: AvatarPackLibrary?
    private let preferences = AppPreferences()
    private lazy var configurationStore = RuntimeConfigurationStore(preferences.privacyConfiguration)
    private let metricsStore = RuntimeMetricsStore()
    private var statusItem: NSStatusItem?
    private var stateMenuItem: NSMenuItem?
    private var connectionMenuItem: NSMenuItem?
    private var packMenuItem: NSMenuItem?
    private var visibilityMenuItem: NSMenuItem?
    private var alwaysOnTopMenuItem: NSMenuItem?
    private var clickThroughMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            let library = try AvatarPackLibrary()
            guard let bundled = findBundledPackDirectory() else {
                presentFatalError("The bundled avatar pack is missing. Rebuild Joyride.app.")
                return
            }
            try library.installBundledPackIfNeeded(from: bundled)
            guard let selectedPack = library.selectedPack else {
                presentFatalError("The avatar library is empty.")
                return
            }
            self.library = library
            configureStatusMenu()

            let windowController = AvatarWindowController(pack: selectedPack) { [metricsStore] receivedAt in
                metricsStore.rendered(receivedAt: receivedAt, presentedAt: Date())
            }
            self.windowController = windowController
            updatePackMenu(selectedPack)

            coordinator = AvatarStateCoordinator { [weak self] state, source, additionalCount, agents, receivedAt in
                self?.windowController?.present(
                    state: state,
                    source: source,
                    additionalCount: additionalCount,
                    agents: agents,
                    receivedAt: receivedAt
                )
                self?.stateMenuItem?.title = "\(state.displayName) · \(source)\(additionalCount > 0 ? " · +\(additionalCount)" : "")"
                self?.metricsStore.stateSelected(state.rawValue, activeCount: additionalCount + (agents.isEmpty ? 0 : 1))
            }
            coordinator?.setPrivacyMode(preferences.privacyMode)
            coordinator?.start()
            windowController.showWindow(nil)

            settingsController = SettingsWindowController(
                library: library,
                preferences: preferences,
                onPackSelected: { [weak self] pack in
                    self?.windowController?.setPack(pack)
                    self?.updatePackMenu(pack)
                },
                onPrivacyChanged: { [weak self] enabled in
                    self?.configurationStore.update(self?.preferences.privacyConfiguration ?? PrivacyConfiguration(
                        privacyMode: enabled,
                        keywordBlacklist: []
                    ))
                    self?.coordinator?.setPrivacyMode(enabled)
                }
            )
            startServer()
            observeWindowOcclusion()
        } catch {
            presentFatalError(error.localizedDescription)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    @objc private func showSettings() {
        settingsController?.refresh()
        settingsController?.showWindow(nil)
        settingsController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleVisibility() {
        guard let window = windowController?.window else { return }
        if window.isVisible {
            window.orderOut(nil)
            windowController?.setPlaybackEnabled(false)
            visibilityMenuItem?.title = "Show avatar"
        } else {
            windowController?.showWindow(nil)
            windowController?.setPlaybackEnabled(true)
            visibilityMenuItem?.title = "Hide avatar"
        }
    }

    @objc private func dockBottomRight() {
        windowController?.dockBottomRight()
    }

    @objc private func toggleAlwaysOnTop() {
        guard let menuItem = alwaysOnTopMenuItem else { return }
        let enabled = menuItem.state != .on
        menuItem.state = enabled ? .on : .off
        windowController?.setAlwaysOnTop(enabled)
    }

    @objc private func toggleClickThrough() {
        guard let menuItem = clickThroughMenuItem else { return }
        let enabled = menuItem.state != .on
        if enabled {
            let alert = NSAlert()
            alert.messageText = "Enable mouse click-through?"
            alert.informativeText = "The avatar window will ignore the pointer. Use the person icon in the menu bar to disable click-through; Settings and Quit remain available there."
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        menuItem.state = enabled ? .on : .off
        windowController?.setClickThrough(enabled)
    }

    @objc private func previewState(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let state = AvatarStateID(rawValue: rawValue) else { return }
        coordinator?.preview(state)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startServer() {
        let server = LocalHTTPServer(
            eventHandler: { [weak self] event, receivedAt in
                Task { @MainActor in
                    self?.coordinator?.receive(event, at: receivedAt)
                }
            },
            statusHandler: { [weak self] status in
                Task { @MainActor in
                    self?.connectionMenuItem?.title = status
                }
            },
            configurationStore: configurationStore,
            metricsStore: metricsStore
        )
        self.server = server
        do {
            try server.start(port: configuredPort())
        } catch {
            connectionMenuItem?.title = "Local API failed · \(error.localizedDescription)"
        }
    }

    private func configureStatusMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "person.crop.circle.badge.sparkles",
            accessibilityDescription: "Joyride"
        )
        statusItem.button?.toolTip = "Joyride settings and quit; recover click-through here"

        let menu = NSMenu()
        let stateItem = NSMenuItem(title: "Starting", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        stateMenuItem = stateItem

        let connectionItem = NSMenuItem(title: "Starting local API", action: nil, keyEquivalent: "")
        connectionItem.isEnabled = false
        menu.addItem(connectionItem)
        connectionMenuItem = connectionItem

        let packItem = NSMenuItem(title: "Avatar pack", action: nil, keyEquivalent: "")
        packItem.isEnabled = false
        menu.addItem(packItem)
        packMenuItem = packItem
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Avatar Library & Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let visibilityItem = NSMenuItem(title: "Hide avatar", action: #selector(toggleVisibility), keyEquivalent: "")
        visibilityItem.target = self
        menu.addItem(visibilityItem)
        visibilityMenuItem = visibilityItem

        let dockItem = NSMenuItem(title: "Dock at bottom right", action: #selector(dockBottomRight), keyEquivalent: "")
        dockItem.target = self
        menu.addItem(dockItem)

        let alwaysOnTopItem = NSMenuItem(title: "Always on top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = .on
        menu.addItem(alwaysOnTopItem)
        alwaysOnTopMenuItem = alwaysOnTopItem

        let clickThroughItem = NSMenuItem(title: "Mouse click-through (recover here)", action: #selector(toggleClickThrough), keyEquivalent: "")
        clickThroughItem.target = self
        menu.addItem(clickThroughItem)
        clickThroughMenuItem = clickThroughItem

        let previewItem = NSMenuItem(title: "Preview all 8 states", action: nil, keyEquivalent: "")
        let previewMenu = NSMenu()
        for state in AvatarStateID.allCases {
            let item = NSMenuItem(title: state.displayName, action: #selector(previewState(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = state.rawValue
            previewMenu.addItem(item)
        }
        previewItem.submenu = previewMenu
        menu.addItem(previewItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Joyride", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func updatePackMenu(_ pack: InstalledAvatarPack) {
        packMenuItem?.title = "Avatar pack · \(pack.name) · \(pack.isCertified ? "Certified" : "Uncertified")"
    }

    private func observeWindowOcclusion() {
        guard let window = windowController?.window else { return }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor in
                self?.windowController?.setPlaybackEnabled(window?.occlusionState.contains(.visible) == true)
            }
        }
    }

    private func configuredPort() -> UInt16 {
        guard let rawValue = ProcessInfo.processInfo.environment["AGENT_AVATAR_PORT"],
              let port = UInt16(rawValue), port > 0 else { return 8_765 }
        return port
    }

    private func findBundledPackDirectory() -> URL? {
        if let configured = ProcessInfo.processInfo.environment["AGENT_AVATAR_PACK"] {
            let url = URL(fileURLWithPath: configured, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) {
                return url
            }
        }
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let pack = resourceURL.appendingPathComponent("packs/default", isDirectory: true)
        return FileManager.default.fileExists(atPath: pack.appendingPathComponent("manifest.json").path) ? pack : nil
    }

    private func presentFatalError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Joyride could not start"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
