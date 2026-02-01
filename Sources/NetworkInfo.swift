import Darwin
import Foundation

enum NetworkInfo {
    static func localIPv4Addresses() -> [String] {
        var addresses = Set<String>()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if !isUp || !isRunning || isLoopback {
                ptr = interface.ifa_next
                continue
            }

            guard let addr = interface.ifa_addr else {
                ptr = interface.ifa_next
                continue
            }

            if addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let ip = String(cString: hostname)
                    if !ip.hasPrefix("127."),
                       !ip.hasPrefix("169.254."),
                       ip != "0.0.0.0" {
                        addresses.insert(ip)
                    }
                }
            }

            ptr = interface.ifa_next
        }

        return addresses.sorted()
    }
}
