import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = ConfigStore.shared
    private var config: AppConfig
    private let serviceManager = ServiceManager()

    override init() {
        self.config = store.load()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenu.setupMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "saka"
        rebuildMenu()
        refreshExternalStates()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if config.services.isEmpty {
            let emptyItem = NSMenuItem(title: "No services configured", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for service in config.services {
                menu.addItem(makeServiceItem(service))
            }
        }

        menu.addItem(NSMenuItem.separator())

        let startAllItem = NSMenuItem(title: "Start All", action: #selector(startAll(_:)), keyEquivalent: "")
        startAllItem.target = self
        menu.addItem(startAllItem)

        let stopAllItem = NSMenuItem(title: "Stop All", action: #selector(stopAll(_:)), keyEquivalent: "")
        stopAllItem.target = self
        menu.addItem(stopAllItem)

        let restartAllItem = NSMenuItem(title: "Restart All", action: #selector(restartAll(_:)), keyEquivalent: "")
        restartAllItem.target = self
        menu.addItem(restartAllItem)

        menu.addItem(NSMenuItem.separator())

        let addItem = NSMenuItem(title: "+ Add Service", action: #selector(addService(_:)), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)

        let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig(_:)), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let editItem = NSMenuItem(title: "Edit Config", action: #selector(openConfig(_:)), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshExternalStates(openUrls: Bool = false) {
        for service in config.services {
            serviceManager.refreshExternalState(service: service, appConfig: config, openUrls: openUrls) { [weak self] in
                self?.rebuildMenu()
            }
        }
    }

    private func makeServiceItem(_ service: ServiceConfig) -> NSMenuItem {
        let state = serviceManager.state(for: service.id)
        let title = "\(service.label) — \(state.displayName)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

        let submenu = NSMenu()

        let startItem = NSMenuItem(title: "Start", action: #selector(startService(_:)), keyEquivalent: "")
        startItem.target = self
        startItem.representedObject = service.id
        startItem.isEnabled = (state == .stopped || state == .unhealthy)
        submenu.addItem(startItem)

        let canStop = serviceManager.canStop(service: service)
        let stopItem = NSMenuItem(title: "Stop", action: #selector(stopService(_:)), keyEquivalent: "")
        stopItem.target = self
        stopItem.representedObject = service.id
        stopItem.isEnabled = (state != .stopped && canStop)
        submenu.addItem(stopItem)

        let restartItem = NSMenuItem(title: "Restart", action: #selector(restartService(_:)), keyEquivalent: "")
        restartItem.target = self
        restartItem.representedObject = service.id
        restartItem.isEnabled = (state != .stopped && canStop)
        submenu.addItem(restartItem)

        let infoItem = NSMenuItem(title: "Info…", action: #selector(showInfo(_:)), keyEquivalent: "")
        infoItem.target = self
        infoItem.representedObject = service.id
        submenu.addItem(infoItem)

        let urls = service.effectiveOpenUrls()
        if !urls.isEmpty {
            let openItem = NSMenuItem(title: "Open", action: nil, keyEquivalent: "")
            let openMenu = NSMenu()
            for url in urls {
                let urlItem = NSMenuItem(title: url, action: #selector(openURL(_:)), keyEquivalent: "")
                urlItem.target = self
                urlItem.representedObject = url
                openMenu.addItem(urlItem)
            }
            openItem.submenu = openMenu
            submenu.addItem(openItem)
        }

        let logItem = NSMenuItem(title: "View Log", action: #selector(viewLog(_:)), keyEquivalent: "")
        logItem.target = self
        logItem.representedObject = service.id
        submenu.addItem(logItem)

        item.submenu = submenu
        return item
    }

    @objc private func addService(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        guard let service = UIFlows.promptAddService() else { return }
        if let error = store.validate(service: service) {
            UIFlows.showError(message: error)
            return
        }
        config.services.append(service)
        store.save(config)
        rebuildMenu()
    }

    @objc private func reloadConfig(_ sender: NSMenuItem) {
        config = store.load()
        serviceManager.stopOrphans(validServiceIds: Set(config.services.map { $0.id })) { }
        rebuildMenu()
        refreshExternalStates()
    }

    @objc private func openConfig(_ sender: NSMenuItem) {
        store.openInEditor()
    }

    @objc private func startService(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let service = config.services.first(where: { $0.id == id }) else { return }
        serviceManager.start(service: service, appConfig: config) { [weak self] in
            self?.rebuildMenu()
        }
    }

    @objc private func stopService(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let service = config.services.first(where: { $0.id == id }) else { return }
        serviceManager.stop(service: service, appConfig: config) { [weak self] in
            self?.rebuildMenu()
        }
    }

    @objc private func restartService(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let service = config.services.first(where: { $0.id == id }) else { return }
        serviceManager.restart(service: service, appConfig: config) { [weak self] in
            self?.rebuildMenu()
        }
    }

    @objc private func showInfo(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let service = config.services.first(where: { $0.id == id }) else { return }
        let info = serviceManager.info(for: service)

        var lines: [String] = []
        lines.append("Status: \(info.state.displayName)")
        if let pid = info.pid {
            lines.append("PID: \(pid)")
        }
        if !info.command.isEmpty {
            lines.append("Command: \(info.command)")
        }
        if let dir = info.workingDir, !dir.isEmpty {
            lines.append("Working Dir: \(dir)")
        }
        if !info.ports.isEmpty {
            lines.append("Ports: \(info.ports.map(String.init).joined(separator: ", "))")
        }
        if !info.healthChecks.isEmpty {
            lines.append("Health Checks: \(info.healthChecks.joined(separator: ", "))")
        }
        if !info.openUrls.isEmpty {
            lines.append("Open URLs: \(info.openUrls.joined(separator: ", "))")
        }

        let alert = NSAlert()
        alert.messageText = service.label
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func startAll(_ sender: NSMenuItem) {
        for service in config.services {
            serviceManager.start(service: service, appConfig: config) { [weak self] in
                self?.rebuildMenu()
            }
        }
    }

    @objc private func stopAll(_ sender: NSMenuItem) {
        for service in config.services {
            if serviceManager.canStop(service: service) {
                serviceManager.stop(service: service, appConfig: config) { [weak self] in
                    self?.rebuildMenu()
                }
            }
        }
    }

    @objc private func restartAll(_ sender: NSMenuItem) {
        for service in config.services {
            if serviceManager.canStop(service: service) {
                serviceManager.restart(service: service, appConfig: config) { [weak self] in
                    self?.rebuildMenu()
                }
            }
        }
    }

    @objc private func openURL(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func viewLog(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let url = serviceManager.logURL(for: id) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}

private extension ServiceState {
    var displayName: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting"
        case .running:
            return "Running"
        case .unhealthy:
            return "Stopped"
        }
    }
}
