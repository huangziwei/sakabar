import Foundation

final class HealthChecker {
    private let queue = DispatchQueue(label: "sakabar.health", qos: .background)
    private var timers: [UUID: DispatchSourceTimer] = [:]
    private var inFlight: Set<UUID> = []

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

    private func probe(checks: [URL], completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var allOK = true
        let lock = NSLock()

        for url in checks {
            group.enter()
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 2
            let task = URLSession.shared.dataTask(with: request) { _, response, error in
                defer { group.leave() }
                if error != nil {
                    lock.lock()
                    allOK = false
                    lock.unlock()
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    lock.lock()
                    allOK = false
                    lock.unlock()
                    return
                }
                if !(200...399).contains(http.statusCode) {
                    lock.lock()
                    allOK = false
                    lock.unlock()
                }
            }
            task.resume()
        }

        group.notify(queue: queue) {
            completion(allOK)
        }
    }
}
