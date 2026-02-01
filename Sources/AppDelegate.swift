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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuUI.statusBarIcon()
            button.imagePosition = .imageOnly
            button.title = ""
        }
        rebuildMenu()
        refreshExternalStates()
        maybePromptApplicationsSymlink()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(MenuUI.headerItem(appName: "Sakabar", summary: menuSummaryText()))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(MenuUI.sectionHeader("Services"))
        if config.services.isEmpty {
            menu.addItem(MenuUI.placeholderItem("No services configured"))
        } else {
            for service in config.services {
                menu.addItem(makeServiceItem(service))
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(MenuUI.sectionHeader("Actions"))

        let hasServices = !config.services.isEmpty
        let startAllItem = MenuUI.menuItem(title: "Start All", action: #selector(startAll(_:)), target: self, symbolName: "play.fill")
        startAllItem.isEnabled = hasServices
        menu.addItem(startAllItem)

        let stopAllItem = MenuUI.menuItem(title: "Stop All", action: #selector(stopAll(_:)), target: self, symbolName: "stop.fill")
        stopAllItem.isEnabled = hasServices
        menu.addItem(stopAllItem)

        let restartAllItem = MenuUI.menuItem(title: "Restart All", action: #selector(restartAll(_:)), target: self, symbolName: "arrow.clockwise")
        restartAllItem.isEnabled = hasServices
        menu.addItem(restartAllItem)

        let refreshItem = MenuUI.menuItem(title: "Refresh Status", action: #selector(refreshStatus(_:)), target: self, symbolName: "arrow.clockwise.circle")
        refreshItem.isEnabled = hasServices
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(MenuUI.sectionHeader("Config"))

        let addItem = MenuUI.menuItem(title: "Add Service", action: #selector(addService(_:)), target: self, symbolName: "plus")
        menu.addItem(addItem)

        let reloadItem = MenuUI.menuItem(title: "Reload Config", action: #selector(reloadConfig(_:)), target: self, symbolName: "arrow.triangle.2.circlepath")
        menu.addItem(reloadItem)

        let editItem = MenuUI.menuItem(title: "Edit Config", action: #selector(openConfig(_:)), target: self, symbolName: "pencil")
        menu.addItem(editItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(MenuUI.sectionHeader("App"))

        if shouldShowApplicationsSymlinkAction() {
            let symlinkItem = MenuUI.menuItem(title: "Add to /Applications", action: #selector(addApplicationsSymlink(_:)), target: self, symbolName: "link.badge.plus")
            menu.addItem(symlinkItem)
        }

        let quitItem = MenuUI.menuItem(title: "Quit", action: #selector(quitApp(_:)), target: self, symbolName: "power")
        quitItem.keyEquivalent = "q"
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
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = MenuUI.serviceTitle(label: service.label, status: state.displayName)
        item.image = MenuUI.statusImage(for: state)

        let submenu = NSMenu()

        let startItem = MenuUI.menuItem(title: "Start", action: #selector(startService(_:)), target: self, symbolName: "play.fill")
        startItem.representedObject = service.id
        startItem.isEnabled = (state == .stopped || state == .unhealthy)
        submenu.addItem(startItem)

        let canStop = serviceManager.canStop(service: service)
        let stopItem = MenuUI.menuItem(title: "Stop", action: #selector(stopService(_:)), target: self, symbolName: "stop.fill")
        stopItem.representedObject = service.id
        stopItem.isEnabled = (state != .stopped && canStop)
        submenu.addItem(stopItem)

        let restartItem = MenuUI.menuItem(title: "Restart", action: #selector(restartService(_:)), target: self, symbolName: "arrow.clockwise")
        restartItem.representedObject = service.id
        restartItem.isEnabled = (state != .stopped && canStop)
        submenu.addItem(restartItem)

        submenu.addItem(NSMenuItem.separator())

        let openGroups = openUrlGroups(for: service, state: state)
        if !openGroups.local.isEmpty || !openGroups.lan.isEmpty {
            let openItem = NSMenuItem(title: "Open", action: nil, keyEquivalent: "")
            openItem.image = MenuUI.symbolImage(name: "link")
            let openMenu = NSMenu()
            let localUrls = openGroups.local
            let lanUrls = openGroups.lan

            if !localUrls.isEmpty && !lanUrls.isEmpty {
                openMenu.addItem(MenuUI.sectionHeader("Local"))
            }
            for url in localUrls {
                let urlItem = MenuUI.menuItem(title: url, action: #selector(openURL(_:)), target: self, symbolName: "arrow.up.right.square")
                urlItem.target = self
                urlItem.representedObject = url
                openMenu.addItem(urlItem)
            }

            if !lanUrls.isEmpty {
                if !localUrls.isEmpty {
                    openMenu.addItem(NSMenuItem.separator())
                    openMenu.addItem(MenuUI.sectionHeader("LAN"))
                }
                for url in lanUrls {
                    let urlItem = MenuUI.menuItem(title: url, action: #selector(openURL(_:)), target: self, symbolName: "wifi")
                    urlItem.target = self
                    urlItem.representedObject = url
                    openMenu.addItem(urlItem)
                }
            }
            openItem.submenu = openMenu
            submenu.addItem(openItem)
        }

        let logItem = MenuUI.menuItem(title: "View Log", action: #selector(viewLog(_:)), target: self, symbolName: "doc.text")
        logItem.representedObject = service.id
        submenu.addItem(logItem)

        let editItem = MenuUI.menuItem(title: "Edit...", action: #selector(editService(_:)), target: self, symbolName: "pencil")
        editItem.representedObject = service.id
        submenu.addItem(editItem)

        submenu.addItem(NSMenuItem.separator())

        let infoItem = MenuUI.menuItem(title: "Info...", action: #selector(showInfo(_:)), target: self, symbolName: "info.circle")
        infoItem.representedObject = service.id
        submenu.addItem(infoItem)

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

    @objc private func refreshStatus(_ sender: NSMenuItem) {
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

    @objc private func editService(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let index = config.services.firstIndex(where: { $0.id == id }) else { return }
        let service = config.services[index]
        NSApp.activate(ignoringOtherApps: true)
        guard let updated = UIFlows.promptEditService(service: service) else { return }
        if let error = store.validate(service: updated) {
            UIFlows.showError(message: error)
            return
        }
        config.services[index] = updated
        store.save(config)
        rebuildMenu()
        refreshExternalStates()
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
            return "Unhealthy"
        }
    }
}

private extension AppDelegate {
    func menuSummaryText() -> String {
        guard !config.services.isEmpty else { return "No services configured" }

        var running = 0
        var starting = 0
        var unhealthy = 0
        var stopped = 0

        for service in config.services {
            switch serviceManager.state(for: service.id) {
            case .running:
                running += 1
            case .starting:
                starting += 1
            case .unhealthy:
                unhealthy += 1
            case .stopped:
                stopped += 1
            }
        }

        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if starting > 0 { parts.append("\(starting) starting") }
        if unhealthy > 0 { parts.append("\(unhealthy) unhealthy") }
        if stopped > 0 { parts.append("\(stopped) stopped") }

        if parts.isEmpty {
            return "\(config.services.count) services"
        }
        return parts.joined(separator: " / ")
    }

    func shouldShowApplicationsSymlinkAction() -> Bool {
        !applicationsItemExists()
    }

    func applicationsInstallURL() -> URL {
        let bundleName = Bundle.main.bundleURL.lastPathComponent
        return URL(fileURLWithPath: "/Applications").appendingPathComponent(bundleName)
    }

    func applicationsItemExists() -> Bool {
        FileManager.default.fileExists(atPath: applicationsInstallURL().path)
    }

    func maybePromptApplicationsSymlink() {
        guard !config.didPromptApplicationsSymlink else { return }
        guard shouldShowApplicationsSymlinkAction() else { return }

        let alert = NSAlert()
        alert.messageText = "Add to /Applications?"
        alert.informativeText = "Create a symlink in /Applications for easier launching."
        alert.addButton(withTitle: "Add Symlink")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        config.didPromptApplicationsSymlink = true
        store.save(config)

        if response == .alertFirstButtonReturn {
            addApplicationsSymlink(nil)
        }
    }

    @objc func addApplicationsSymlink(_ sender: NSMenuItem?) {
        let fm = FileManager.default
        let targetURL = applicationsInstallURL()
        if fm.fileExists(atPath: targetURL.path) {
            UIFlows.showError(message: "An item already exists at \(targetURL.path).")
            rebuildMenu()
            return
        }

        do {
            try fm.createSymbolicLink(at: targetURL, withDestinationURL: Bundle.main.bundleURL)
        } catch {
            UIFlows.showError(message: "Could not create symlink: \(error.localizedDescription)")
            return
        }

        rebuildMenu()
    }
    func openUrlGroups(for service: ServiceConfig, state: ServiceState) -> (local: [String], lan: [String]) {
        let localUrls = serviceManager.effectiveOpenUrls(for: service)
        let ports = portCandidates(for: service, state: state, localUrls: localUrls)
        let lanUrls = lanUrls(for: service, ports: ports, localUrls: localUrls)
        return (local: deduped(localUrls), lan: deduped(lanUrls))
    }

    func portCandidates(for service: ServiceConfig, state: ServiceState, localUrls: [String]) -> [Int] {
        if let port = service.port {
            return [port]
        }

        let explicitUrls = service.openUrls ?? []
        let parsedPorts = (explicitUrls + localUrls).compactMap { URL(string: $0)?.port }
        if !parsedPorts.isEmpty {
            return parsedPorts
        }

        if state == .running {
            return serviceManager.info(for: service).ports
        }
        return []
    }

    func lanUrls(for service: ServiceConfig, ports: [Int], localUrls: [String]) -> [String] {
        guard !ports.isEmpty else { return [] }
        let ips = NetworkInfo.localIPv4Addresses()
        guard !ips.isEmpty else { return [] }
        let scheme = preferredScheme(for: service, localUrls: localUrls)

        var urls: [String] = []
        for ip in ips {
            for port in ports {
                urls.append("\(scheme)://\(ip):\(port)")
            }
        }
        return urls
    }

    func preferredScheme(for service: ServiceConfig, localUrls: [String]) -> String {
        if let urlString = localUrls.first,
           let url = URL(string: urlString),
           let scheme = url.scheme {
            return scheme
        }
        if let scheme = service.scheme?.lowercased(), !scheme.isEmpty {
            return scheme
        }
        if let urlString = service.openUrls?.first,
           let url = URL(string: urlString),
           let scheme = url.scheme,
           !scheme.isEmpty {
            return scheme
        }
        if let urlString = service.healthChecks?.first,
           let url = URL(string: urlString),
           let scheme = url.scheme,
           !scheme.isEmpty {
            return scheme
        }
        return "http"
    }

    func deduped(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for url in urls {
            if seen.insert(url).inserted {
                result.append(url)
            }
        }
        return result
    }
}
