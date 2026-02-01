import Foundation

final class HealthChecker {
    private let queue = DispatchQueue(label: "sakabar.health", qos: .background)
    private var timers: [UUID: DispatchSourceTimer] = [:]
    private var inFlight: Set<UUID> = []
    private let insecureDelegate = LocalhostTrustDelegate()
    private lazy var insecureSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        return URLSession(configuration: config, delegate: insecureDelegate, delegateQueue: nil)
    }()

    func start(
        checks: [URL],
        timeout: TimeInterval,
        interval: TimeInterval,
        onReady: @escaping () -> Void,
        onTimeout: @escaping () -> Void
    ) -> UUID {
        let token = UUID()
        let startTime = Date()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if Date().timeIntervalSince(startTime) > timeout {
                self.cancel(token)
                DispatchQueue.main.async {
                    onTimeout()
                }
                return
            }

            if self.inFlight.contains(token) {
                return
            }
            self.inFlight.insert(token)

            self.probe(checks: checks) { ok in
                self.inFlight.remove(token)
                if ok {
                    self.cancel(token)
                    DispatchQueue.main.async {
                        onReady()
                    }
                }
            }
        }
        timers[token] = timer
        timer.resume()
        return token
    }

    func cancel(_ token: UUID) {
        if let timer = timers[token] {
            timer.cancel()
            timers.removeValue(forKey: token)
        }
        inFlight.remove(token)
    }

    func checkOnce(checks: [URL], completion: @escaping (Bool) -> Void) {
        probe(checks: checks, completion: completion)
    }

    func detectScheme(
        host: String,
        port: Int,
        timeout: TimeInterval,
        interval: TimeInterval,
        completion: @escaping (String?) -> Void
    ) -> UUID {
        let token = UUID()
        let startTime = Date()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if Date().timeIntervalSince(startTime) > timeout {
                self.cancel(token)
                completion(nil)
                return
            }

            if self.inFlight.contains(token) {
                return
            }
            self.inFlight.insert(token)

            self.detectSchemeOnce(host: host, port: port) { scheme in
                self.inFlight.remove(token)
                if let scheme {
                    self.cancel(token)
                    completion(scheme)
                }
            }
        }
        timers[token] = timer
        timer.resume()
        return token
    }

    func detectSchemeOnce(host: String, port: Int, completion: @escaping (String?) -> Void) {
        probeScheme(host: host, port: port, scheme: "https", allowInsecureLocalhost: true) { [weak self] ok in
            guard let self else { return }
            if ok {
                completion("https")
                return
            }
            self.probeScheme(host: host, port: port, scheme: "http", allowInsecureLocalhost: false) { okHttp in
                completion(okHttp ? "http" : nil)
            }
        }
    }

    private func probe(checks: [URL], completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var allOK = true
        let lock = NSLock()

        for url in checks {
            group.enter()
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 2
            let session = session(for: url)
            let task = session.dataTask(with: request) { _, response, error in
                defer { group.leave() }
                if error != nil {
                    lock.lock()
                    allOK = false
                    lock.unlock()
                    return
                }
                guard response is HTTPURLResponse else {
                    lock.lock()
                    allOK = false
                    lock.unlock()
                    return
                }
            }
            task.resume()
        }

        group.notify(queue: queue) {
            completion(allOK)
        }
    }

    private func probeScheme(
        host: String,
        port: Int,
        scheme: String,
        allowInsecureLocalhost: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = "/"
        guard let url = components.url else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        let session: URLSession
        if scheme == "https" && allowInsecureLocalhost && LocalhostTrustDelegate.isLocalhost(host: host) {
            session = insecureSession
        } else {
            session = URLSession.shared
        }

        let task = session.dataTask(with: request) { _, response, error in
            if error != nil {
                completion(false)
                return
            }
            completion(response is HTTPURLResponse)
        }
        task.resume()
    }

    private func session(for url: URL) -> URLSession {
        guard let scheme = url.scheme, scheme == "https", let host = url.host else {
            return URLSession.shared
        }
        if LocalhostTrustDelegate.isLocalhost(host: host) {
            return insecureSession
        }
        return URLSession.shared
    }
}

private final class LocalhostTrustDelegate: NSObject, URLSessionDelegate {
    static func isLocalhost(host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }
        return false
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if LocalhostTrustDelegate.isLocalhost(host: challenge.protectionSpace.host) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
