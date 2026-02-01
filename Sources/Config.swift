import AppKit
import Foundation

struct AppConfig: Codable {
    var version: Int
    var services: [ServiceConfig]
    var defaultShell: String
    var pathAdditions: [String]
    var healthTimeoutSeconds: TimeInterval
    var healthIntervalSeconds: TimeInterval

    static let currentVersion = 1

    static func `default`() -> AppConfig {
        AppConfig(
            version: currentVersion,
            services: [],
            defaultShell: "/bin/zsh",
            pathAdditions: ["/opt/homebrew/bin", "/usr/local/bin", "/opt/podman/bin"],
            healthTimeoutSeconds: 30,
            healthIntervalSeconds: 1
        )
    }
}

struct ServiceConfig: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var command: String?
    var args: [String]?
    var workingDir: String?
    var env: [String: String]?
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

        return nil
    }
}
