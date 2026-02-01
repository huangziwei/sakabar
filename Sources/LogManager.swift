import AppKit
import Foundation

final class LogManager {
    private let logsDir: URL

    init() {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        self.logsDir = base.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("sakabar", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    func logURL(for serviceId: String) -> URL {
        logsDir.appendingPathComponent("\(serviceId).log")
    }

    func openLog(for serviceId: String) -> (url: URL, handle: FileHandle?) {
        let url = logURL(for: serviceId)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: Data())
        }
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        return (url, handle)
    }
}
