import Darwin
import Foundation

final class PortDetector {
    func detectPorts(pid: pid_t) -> [Int] {
        guard pid > 0 else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-p", String(pid)]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        var ports: [Int] = []
        for line in output.split(separator: "\n") {
            // Example: node 123 user ... TCP 127.0.0.1:3000 (LISTEN)
            if let range = line.range(of: "TCP ") {
                let rest = line[range.upperBound...]
                if let colonIndex = rest.lastIndex(of: ":") {
                    let portPart = rest[rest.index(after: colonIndex)...]
                    let portString = portPart.split(separator: " ").first ?? ""
                    if let port = Int(portString) {
                        ports.append(port)
                    }
                }
            }
        }

        return Array(Set(ports)).sorted()
    }

    func detectPids(listeningOn ports: [Int]) -> [pid_t] {
        let unique = Array(Set(ports)).sorted()
        var results: [pid_t] = []
        for port in unique {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                continue
            }

            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                continue
            }

            for line in output.split(separator: "\n") {
                if let pid = Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    results.append(pid_t(pid))
                }
            }
        }
        return Array(Set(results)).sorted()
    }
}
