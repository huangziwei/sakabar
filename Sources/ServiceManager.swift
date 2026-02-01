import AppKit
import Darwin
import Foundation

enum ServiceState {
    case stopped
    case starting
    case running
    case externalRunning
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
            healthChecks: service.healthChecks ?? [],
            openUrls: service.openUrls ?? []
        )
    }

    func refreshExternalStates(services: [ServiceConfig], appConfig: AppConfig, onChange: @escaping () -> Void) {
        for service in services {
            if processes[service.id] != nil {
                continue
            }
            let checks = (service.healthChecks ?? []).compactMap { URL(string: $0) }
            guard !checks.isEmpty else {
                if states[service.id] == .externalRunning {
                    states[service.id] = .stopped
                    onChange()
                }
                continue
            }
            healthChecker.checkOnce(checks: checks) { [weak self] ok in
                guard let self else { return }
                if self.processes[service.id] != nil {
                    return
                }
                let nextState: ServiceState = ok ? .externalRunning : .stopped
                if self.states[service.id] != nextState {
                    self.states[service.id] = nextState
                    DispatchQueue.main.async {
                        onChange()
                    }
                }
            }
        }
    }

    func start(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void) {
        if let current = states[service.id], current != .stopped {
            return
        }

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

        let checks = (service.healthChecks ?? []).compactMap { URL(string: $0) }
        if checks.isEmpty {
            markRunning(service: service, onStateChange: onStateChange)
        } else {
            let token = healthChecker.start(
                checks: checks,
                timeout: appConfig.healthTimeoutSeconds,
                interval: appConfig.healthIntervalSeconds,
                onReady: { [weak self] in
                    self?.markRunning(service: service, onStateChange: onStateChange)
                },
                onTimeout: { [weak self] in
                    self?.markRunning(service: service, onStateChange: onStateChange, openUrls: false)
                }
            )
            healthTokens[service.id] = token
        }
    }

    func stop(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void) {
        cancelHealthCheck(serviceId: service.id)

        if let stopCommand = service.stopCommand, !stopCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runStopCommand(stopCommand, workingDir: service.workingDir, env: makeEnvironment(service: service, appConfig: appConfig))
        }

        if let process = processes[service.id] {
            let pid = process.processIdentifier
            if pid > 0 {
                _ = killpg(pid, SIGTERM)
            }
            process.terminate()
            processes.removeValue(forKey: service.id)
        }

        states[service.id] = .stopped
        closeLog(serviceId: service.id)
        onStateChange()
    }

    func restart(service: ServiceConfig, appConfig: AppConfig, onStateChange: @escaping () -> Void) {
        stop(service: service, appConfig: appConfig) { }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start(service: service, appConfig: appConfig, onStateChange: onStateChange)
        }
    }

    func stopOrphans(validServiceIds: Set<String>, onStateChange: @escaping () -> Void) {
        for (id, process) in processes where !validServiceIds.contains(id) {
            let pid = process.processIdentifier
            if pid > 0 {
                _ = killpg(pid, SIGTERM)
            }
            process.terminate()
            processes.removeValue(forKey: id)
            states[id] = .stopped
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

        if let workingDir = service.workingDir, !workingDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        }

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
        let additions = appConfig.pathAdditions.joined(separator: ":")
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

    private func portsForService(_ service: ServiceConfig) -> [Int] {
        var ports: [Int] = []
        let urls = (service.healthChecks ?? []) + (service.openUrls ?? [])
        for raw in urls {
            guard let url = URL(string: raw), let port = url.port else {
                continue
            }
            ports.append(port)
        }
        return Array(Set(ports)).sorted()
    }

    private func runStopCommand(_ command: String, workingDir: String?, env: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        if let workingDir = workingDir, !workingDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        }
        process.environment = env
        try? process.run()
    }

    private func markRunning(service: ServiceConfig, onStateChange: @escaping () -> Void, openUrls: Bool = true) {
        guard let process = processes[service.id], process.isRunning else {
            states[service.id] = .stopped
            onStateChange()
            return
        }
        states[service.id] = .running
        onStateChange()

        if openUrls, service.autoOpen, let urls = service.openUrls {
            DispatchQueue.main.async {
                for urlString in urls {
                    if let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
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
}
