import AppKit
import Darwin
import Foundation

enum ServiceState {
    case stopped
    case starting
    case running
    case unhealthy
}

struct ServiceInfo {
    let state: ServiceState
    let pid: pid_t?
    let command: String
    let workingDir: String?
    let ports: [Int]
    let healthChecks: [String]
    let openUrls: [String]
}

final class ServiceManager {
    private var states: [String: ServiceState] = [:]
    private var processes: [String: Process] = [:]
    private var logHandles: [String: FileHandle] = [:]
    private var logURLs: [String: URL] = [:]
    private var healthTokens: [String: UUID] = [:]
    private var healthTimers: [String: DispatchSourceTimer] = [:]
    private var healthInFlight: Set<String> = []
    private var externalMonitoring: Set<String> = []
    private let healthChecker = HealthChecker()
    private let logManager = LogManager()
    private let portDetector = PortDetector()

    func state(for id: String) -> ServiceState {
        states[id] ?? .stopped
    }

    func logURL(for id: String) -> URL? {
        if let url = logURLs[id] {
            return url
        }
        return logManager.logURL(for: id)
    }

    func canStop(service: ServiceConfig) -> Bool {
        if processes[service.id] != nil {
            return true
        }
        let stopCommand = service.stopCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stopCommand.isEmpty {
            return true
        }
        return canStopByPort(service: service)
    }

    func info(for service: ServiceConfig) -> ServiceInfo {
        let state = self.state(for: service.id)
        let process = processes[service.id]
        let pid = process?.processIdentifier
        let command = displayCommand(for: service)
        let ports: [Int]
        if let pid, state == .running {
            ports = portDetector.detectPorts(pid: pid)
        } else {
            ports = []
        }

        return ServiceInfo(
            state: state,
            pid: pid,
            command: command,
            workingDir: service.workingDir,
            ports: ports,
            healthChecks: effectiveHealthChecks(for: service),
            openUrls: effectiveOpenUrls(for: service)
        )
    }

    func start(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void) {
        if processes[service.id] != nil {
            restart(service: service, appConfig: appConfig, onStateChange: onStateChange)
            return
        }

        let checks = effectiveHealthChecks(for: service).compactMap { URL(string: $0) }
        if !checks.isEmpty {
            healthChecker.checkOnce(checks: checks) { [weak self] ok in
                guard let self else { return }
                if ok {
                    self.markExternalRunning(service: service, appConfig: appConfig, onStateChange: onStateChange, openUrls: true)
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.startManagedProcess(service: service, appConfig: appConfig, onStateChange: onStateChange)
                    }
                }
            }
            return
        }

        startManagedProcess(service: service, appConfig: appConfig, onStateChange: onStateChange)
    }

    func refreshExternalState(service: ServiceConfig, appConfig: AppConfig, openUrls: Bool = false, onStateChange: @escaping () -> Void) {
        guard processes[service.id] == nil else { return }
        let checks = effectiveHealthChecks(for: service).compactMap { URL(string: $0) }
        guard !checks.isEmpty else { return }
        healthChecker.checkOnce(checks: checks) { [weak self] ok in
            guard let self else { return }
            if ok {
                self.markExternalRunning(service: service, appConfig: appConfig, onStateChange: onStateChange, openUrls: openUrls)
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.externalMonitoring.remove(service.id)
                    self.states[service.id] = .stopped
                    onStateChange()
                }
            }
        }
    }

    private func startManagedProcess(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void) {
        externalMonitoring.remove(service.id)
        guard let process = buildProcess(service: service, appConfig: appConfig) else {
            return
        }

        let logTarget = logManager.openLog(for: service.id)
        if let handle = logTarget.handle {
            process.standardOutput = handle
            process.standardError = handle
            logHandles[service.id] = handle
        }
        logURLs[service.id] = logTarget.url

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.handleTermination(serviceId: service.id, process: proc, onStateChange: onStateChange)
            }
        }

        do {
            try process.run()
        } catch {
            states[service.id] = .stopped
            onStateChange()
            return
        }

        let pid = process.processIdentifier
        if pid > 0 {
            _ = setpgid(pid, pid)
        }

        processes[service.id] = process
        states[service.id] = .starting
        onStateChange()

        let checks = effectiveHealthChecks(for: service).compactMap { URL(string: $0) }
        if checks.isEmpty {
            markRunning(service: service, appConfig: appConfig, onStateChange: onStateChange)
        } else {
            let token = healthChecker.start(
                checks: checks,
                timeout: appConfig.healthTimeoutSeconds,
                interval: appConfig.healthIntervalSeconds,
                onReady: { [weak self] in
                    self?.markRunning(service: service, appConfig: appConfig, onStateChange: onStateChange)
                },
                onTimeout: { [weak self] in
                    self?.markUnhealthy(service: service, appConfig: appConfig, onStateChange: onStateChange)
                }
            )
            healthTokens[service.id] = token
        }
    }

    func stop(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void) {
        let hasProcess = (processes[service.id] != nil)
        let stopCommand = service.stopCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasStopCommand = !stopCommand.isEmpty
        let ports = portsForService(service)
        let canKillByPort = !hasStopCommand && !ports.isEmpty
        if !hasProcess && !hasStopCommand && !canKillByPort {
            return
        }

        cancelHealthCheck(serviceId: service.id)
        cancelHealthMonitor(serviceId: service.id)
        externalMonitoring.remove(service.id)

        if hasStopCommand {
            runStopCommand(stopCommand, workingDir: service.workingDir, env: makeEnvironment(service: service, appConfig: appConfig))
        }

        if let process = processes[service.id] {
            let pid = process.processIdentifier
            if pid > 0 {
                _ = killpg(pid, SIGTERM)
            }
            process.terminate()
            processes.removeValue(forKey: service.id)
        } else if canKillByPort {
            killByPort(ports)
        }

        states[service.id] = .stopped
        closeLog(serviceId: service.id)
        onStateChange()
    }

    func restart(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void) {
        guard canStop(service: service) else { return }
        stop(service: service, appConfig: appConfig) { }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start(service: service, appConfig: appConfig, onStateChange: onStateChange)
        }
    }

    func stopOrphans(validServiceIds: Set<String>, onStateChange: @escaping () -> Void) {
        let orphanProcessIds = processes.keys.filter { !validServiceIds.contains($0) }
        for id in orphanProcessIds {
            guard let process = processes[id] else { continue }
            let pid = process.processIdentifier
            if pid > 0 {
                _ = killpg(pid, SIGTERM)
            }
            process.terminate()
            processes.removeValue(forKey: id)
            states[id] = .stopped
            cancelHealthCheck(serviceId: id)
            cancelHealthMonitor(serviceId: id)
            externalMonitoring.remove(id)
            closeLog(serviceId: id)
        }

        let orphanStateIds = states.keys.filter { !validServiceIds.contains($0) }
        for id in orphanStateIds {
            cancelHealthCheck(serviceId: id)
            cancelHealthMonitor(serviceId: id)
            externalMonitoring.remove(id)
            states.removeValue(forKey: id)
            closeLog(serviceId: id)
        }
        onStateChange()
    }

    private func buildProcess(service: ServiceConfig, appConfig: AppConfig) -> Process? {
        let process = Process()

        if let command = service.command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.executableURL = URL(fileURLWithPath: appConfig.defaultShell)
            process.arguments = ["-lc", command]
        } else if let args = service.args, !args.isEmpty {
            if args[0].contains("/") {
                process.executableURL = URL(fileURLWithPath: args[0])
                process.arguments = Array(args.dropFirst())
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = args
            }
        } else {
            return nil
        }

        process.environment = makeEnvironment(service: service, appConfig: appConfig)

        process.currentDirectoryURL = effectiveWorkingDirectory(path: service.workingDir)

        return process
    }

    private func displayCommand(for service: ServiceConfig) -> String {
        if let command = service.command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return command
        }
        if let args = service.args, !args.isEmpty {
            return args.joined(separator: " ")
        }
        return ""
    }

    private func makeEnvironment(service: ServiceConfig, appConfig: AppConfig) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var additionsList = appConfig.pathAdditions
        let homeLocalBin = NSHomeDirectory() + "/.local/bin"
        if !additionsList.contains(homeLocalBin) {
            additionsList.append(homeLocalBin)
        }
        let additions = additionsList.joined(separator: ":")
        if !additions.isEmpty {
            let current = env["PATH"] ?? ""
            env["PATH"] = current.isEmpty ? additions : (additions + ":" + current)
        }
        if let overrides = service.env {
            for (key, value) in overrides {
                env[key] = value
            }
        }
        return env
    }

    func effectiveHealthChecks(for service: ServiceConfig) -> [String] {
        service.effectiveHealthChecks()
    }

    func effectiveOpenUrls(for service: ServiceConfig) -> [String] {
        service.effectiveOpenUrls()
    }

    private func portsForService(_ service: ServiceConfig) -> [Int] {
        var ports: [Int] = []
        let urls = effectiveHealthChecks(for: service) + effectiveOpenUrls(for: service)
        for raw in urls {
            guard let url = URL(string: raw), let port = url.port else {
                continue
            }
            ports.append(port)
        }
        return Array(Set(ports)).sorted()
    }

    private func canStopByPort(service: ServiceConfig) -> Bool {
        !portsForService(service).isEmpty
    }

    private func killByPort(_ ports: [Int]) {
        let pids = portDetector.detectPids(listeningOn: ports)
        for pid in pids where pid > 0 {
            _ = kill(pid, SIGTERM)
        }
    }

    private func openUrlsIfNeeded(service: ServiceConfig) {
        openUrlsNow(service: service)
    }

    private func openUrlsNow(service: ServiceConfig) {
        let urls = service.effectiveOpenUrls()
        for urlString in urls {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func runStopCommand(_ command: String, workingDir: String?, env: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = effectiveWorkingDirectory(path: workingDir)
        process.environment = env
        try? process.run()
    }

    private func effectiveWorkingDirectory(path: String?) -> URL {
        if let workingDir = path?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workingDir.isEmpty {
            return URL(fileURLWithPath: workingDir)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    private func markExternalRunning(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void, openUrls: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.externalMonitoring.insert(service.id)
            self.states[service.id] = .running
            onStateChange()
            self.startHealthMonitor(service: service, appConfig: appConfig, onStateChange: onStateChange, allowExternal: true)

            if openUrls, service.autoOpen {
                self.openUrlsIfNeeded(service: service)
            }
        }
    }

    private func markRunning(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void, openUrls: Bool = true) {
        guard let process = processes[service.id], process.isRunning else {
            states[service.id] = .stopped
            onStateChange()
            return
        }
        externalMonitoring.remove(service.id)
        states[service.id] = .running
        onStateChange()
        startHealthMonitor(service: service, appConfig: appConfig, onStateChange: onStateChange)

        if openUrls, service.autoOpen {
            openUrlsIfNeeded(service: service)
        }
    }

    private func cancelHealthCheck(serviceId: String) {
        if let token = healthTokens[serviceId] {
            healthChecker.cancel(token)
            healthTokens.removeValue(forKey: serviceId)
        }
    }

    private func handleTermination(serviceId: String, process: Process, onStateChange: @escaping () -> Void) {
        if let current = processes[serviceId], current.processIdentifier == process.processIdentifier {
            processes.removeValue(forKey: serviceId)
        }
        cancelHealthCheck(serviceId: serviceId)
        cancelHealthMonitor(serviceId: serviceId)
        externalMonitoring.remove(serviceId)
        states[serviceId] = .stopped
        closeLog(serviceId: serviceId)
        onStateChange()
    }

    private func closeLog(serviceId: String) {
        if let handle = logHandles[serviceId] {
            try? handle.close()
            logHandles.removeValue(forKey: serviceId)
        }
    }

    private func markUnhealthy(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void) {
        guard let process = processes[service.id], process.isRunning else {
            states[service.id] = .stopped
            onStateChange()
            return
        }
        states[service.id] = .unhealthy
        onStateChange()
        startHealthMonitor(service: service, appConfig: appConfig, onStateChange: onStateChange)
    }

    private func startHealthMonitor(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void, allowExternal: Bool = false) {
        let checks = effectiveHealthChecks(for: service).compactMap { URL(string: $0) }
        guard !checks.isEmpty else { return }
        if healthTimers[service.id] != nil {
            return
        }

        let interval = max(1, appConfig.healthIntervalSeconds)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let hasProcess = (self.processes[service.id] != nil)
            if !allowExternal && !hasProcess {
                self.cancelHealthMonitor(serviceId: service.id)
                return
            }
            if allowExternal && !hasProcess && !self.externalMonitoring.contains(service.id) {
                self.cancelHealthMonitor(serviceId: service.id)
                return
            }
            if self.healthInFlight.contains(service.id) {
                return
            }
            self.healthInFlight.insert(service.id)
            self.healthChecker.checkOnce(checks: checks) { ok in
                self.healthInFlight.remove(service.id)
                guard self.processes[service.id] != nil else { return }
                let current = self.states[service.id] ?? .stopped
                let next: ServiceState = ok ? .running : .unhealthy
                if current != next {
                    self.states[service.id] = next
                    DispatchQueue.main.async {
                        onStateChange()
                    }
                }
            }
        }
        healthTimers[service.id] = timer
        timer.resume()
    }

    private func cancelHealthMonitor(serviceId: String) {
        if let timer = healthTimers[serviceId] {
            timer.cancel()
            healthTimers.removeValue(forKey: serviceId)
        }
        healthInFlight.remove(serviceId)
    }
}
