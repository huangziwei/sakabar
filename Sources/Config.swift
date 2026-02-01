import AppKit
import Foundation

struct AppConfig: Codable {
    var version: Int
    var services: [ServiceConfig]
    var defaultShell: String
    var pathAdditions: [String]
    var healthTimeoutSeconds: TimeInterval
    var healthIntervalSeconds: TimeInterval
    var didPromptApplicationsSymlink: Bool

    static let currentVersion = 1

    static func `default`() -> AppConfig {
        AppConfig(
            version: currentVersion,
            services: [],
            defaultShell: "/bin/zsh",
            pathAdditions: [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/opt/podman/bin",
                NSHomeDirectory() + "/.local/bin"
            ],
            healthTimeoutSeconds: 30,
            healthIntervalSeconds: 1,
            didPromptApplicationsSymlink: false
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case services
        case defaultShell
        case pathAdditions
        case healthTimeoutSeconds
        case healthIntervalSeconds
        case didPromptApplicationsSymlink
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion
        services = try container.decodeIfPresent([ServiceConfig].self, forKey: .services) ?? []
        defaultShell = try container.decodeIfPresent(String.self, forKey: .defaultShell) ?? "/bin/zsh"
        pathAdditions = try container.decodeIfPresent([String].self, forKey: .pathAdditions) ?? []
        healthTimeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .healthTimeoutSeconds) ?? 30
        healthIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .healthIntervalSeconds) ?? 1
        didPromptApplicationsSymlink = try container.decodeIfPresent(Bool.self, forKey: .didPromptApplicationsSymlink) ?? false
    }

    init(
        version: Int,
        services: [ServiceConfig],
        defaultShell: String,
        pathAdditions: [String],
        healthTimeoutSeconds: TimeInterval,
        healthIntervalSeconds: TimeInterval,
        didPromptApplicationsSymlink: Bool
    ) {
        self.version = version
        self.services = services
        self.defaultShell = defaultShell
        self.pathAdditions = pathAdditions
        self.healthTimeoutSeconds = healthTimeoutSeconds
        self.healthIntervalSeconds = healthIntervalSeconds
        self.didPromptApplicationsSymlink = didPromptApplicationsSymlink
    }
}

struct ServiceConfig: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var command: String?
    var args: [String]?
    var workingDir: String?
    var env: [String: String]?
    var host: String?
    var port: Int?
    var scheme: String?
    var healthChecks: [String]?
    var openUrls: [String]?
    var stopCommand: String?
    var autoOpen: Bool
    var startAtLogin: Bool

    init(
        id: String = UUID().uuidString,
        label: String,
        command: String?,
        args: [String]? = nil,
        workingDir: String? = nil,
        env: [String: String]? = nil,
        host: String? = nil,
        port: Int? = nil,
        scheme: String? = nil,
        healthChecks: [String]? = nil,
        openUrls: [String]? = nil,
        stopCommand: String? = nil,
        autoOpen: Bool = true,
        startAtLogin: Bool = false
    ) {
        self.id = id
        self.label = label
        self.command = command
        self.args = args
        self.workingDir = workingDir
        self.env = env
        self.host = host
        self.port = port
        self.scheme = scheme
        self.healthChecks = healthChecks
        self.openUrls = openUrls
        self.stopCommand = stopCommand
        self.autoOpen = autoOpen
        self.startAtLogin = startAtLogin
    }
}

final class ConfigStore {
    static let shared = ConfigStore()

    let configURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("sakabar", isDirectory: true)
        self.configURL = dir.appendingPathComponent("config.json")
    }

    func load() -> AppConfig {
        let fm = FileManager.default
        let dir = configURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: configURL.path) {
            let config = AppConfig.default()
            save(config)
            return config
        }

        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            let config = try decoder.decode(AppConfig.self, from: data)
            return config
        } catch {
            let backupURL = configURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? fm.moveItem(at: configURL, to: backupURL)
            let config = AppConfig.default()
            save(config)
            return config
        }
    }

    func save(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            // Ignore save failures; UI will still reflect in-memory config.
        }
    }

    func openInEditor() {
        NSWorkspace.shared.open(configURL)
    }

    func validate(service: ServiceConfig) -> String? {
        if service.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Service name is required."
        }

        let hasCommand = (service.command?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        let hasArgs = (service.args?.isEmpty == false)
        if !hasCommand && !hasArgs {
            return "Command or args are required."
        }

        if let port = service.port, !(1...65535).contains(port) {
            return "Port must be between 1 and 65535."
        }

        return nil
    }
}

extension ServiceConfig {
    func effectiveHost() -> String? {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        if port != nil {
            return "localhost"
        }
        return nil
    }

    func effectiveHealthChecks(schemeOverride: String? = nil) -> [String] {
        if let checks = healthChecks, !checks.isEmpty {
            return checks
        }
        guard let host = effectiveHost(), let port = port else { return [] }
        let scheme = schemeOverride ?? preferredScheme()
        return ["\(scheme)://\(host):\(port)"]
    }

    func effectiveOpenUrls(schemeOverride: String? = nil) -> [String] {
        if let urls = openUrls, !urls.isEmpty {
            return urls
        }
        guard let host = effectiveHost(), let port = port else { return [] }
        let scheme = schemeOverride ?? preferredScheme()
        return ["\(scheme)://\(host):\(port)"]
    }

    private func preferredScheme() -> String {
        if let scheme, !scheme.isEmpty {
            return scheme
        }
        if let urlString = openUrls?.first,
           let url = URL(string: urlString),
           let scheme = url.scheme,
           !scheme.isEmpty {
            return scheme
        }
        if let urlString = healthChecks?.first,
           let url = URL(string: urlString),
           let scheme = url.scheme,
           !scheme.isEmpty {
            return scheme
        }
        return "http"
    }
}
