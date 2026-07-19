import Foundation
import Network

class PingManager: NSObject, ObservableObject {
    @Published var latestLatency: String = "--"
    /// Numeric latest RTT in ms; nil when unknown / timeout / stopped.
    @Published var latestLatencyMs: Double?
    @Published var statsString: String = "--/--/--"
    @Published var statusMessage: String = "Ready"
    @Published var isConnected: Bool = false
    @Published var isRunning: Bool = false
    @Published var averageLatency30s: Double = 0.0
    @Published var pingResults: [Double] = []
    @Published var resolvedIP: String = ""
    @Published var host: String
    /// Seconds between pings. Default 1. Clamped to 1...60.
    @Published var intervalSeconds: Double

    private var queue = DispatchQueue(label: "com.pingapp.ping")
    private var pingTimer: Timer?
    private var isPingInFlight = false

    private static let hostKey = "PingMenuBar.host"
    private static let intervalKey = "PingMenuBar.intervalSeconds"
    private static let defaultHost = "8.8.8.8"
    private static let defaultInterval: Double = 1.0

    override init() {
        let savedHost = UserDefaults.standard.string(forKey: Self.hostKey) ?? Self.defaultHost
        let savedInterval = UserDefaults.standard.object(forKey: Self.intervalKey) as? Double
        self.host = savedHost.isEmpty ? Self.defaultHost : savedHost
        self.intervalSeconds = Self.clampedInterval(savedInterval ?? Self.defaultInterval)
        super.init()
    }

    static func clampedInterval(_ value: Double) -> Double {
        min(60, max(1, value.rounded()))
    }

    /// Start (or restart) continuous pings. Uses `host` and `intervalSeconds`.
    func startPinging(host newHost: String? = nil) {
        if let newHost = newHost?.trimmingCharacters(in: .whitespacesAndNewlines), !newHost.isEmpty {
            host = newHost
            UserDefaults.standard.set(host, forKey: Self.hostKey)
        }

        let target = host
        pingResults.removeAll()
        statusMessage = "Resolving..."
        latestLatency = "--"
        latestLatencyMs = nil
        averageLatency30s = 0.0
        resolvedIP = ""
        isRunning = true
        isConnected = false

        pingTimer?.invalidate()
        pingTimer = nil

        resolveHost(target) { [weak self] resolvedHost in
            guard let self = self else { return }

            DispatchQueue.main.async {
                // Host may have changed while resolving
                guard self.isRunning, self.host == target else { return }

                self.resolvedIP = resolvedHost
                self.statusMessage = "Connecting..."
                self.performPing(host: target)
                self.scheduleTimer(for: target)
            }
        }
    }

    /// Update interval; persists and reschedules if currently running.
    func setInterval(_ seconds: Double) {
        let clamped = Self.clampedInterval(seconds)
        intervalSeconds = clamped
        UserDefaults.standard.set(clamped, forKey: Self.intervalKey)

        guard isRunning else { return }
        scheduleTimer(for: host)
    }

    private func scheduleTimer(for target: String) {
        pingTimer?.invalidate()

        let interval = intervalSeconds
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if self.isRunning, self.host == target {
                self.performPing(host: target)
            } else {
                timer.invalidate()
            }
        }
        // `.common` so pings continue while the menu/popover tracking runs
        RunLoop.main.add(timer, forMode: .common)
        pingTimer = timer
    }

    private func resolveHost(_ host: String, completion: @escaping (String) -> Void) {
        queue.async {
            var hints = addrinfo()
            hints.ai_family = AF_INET // IPv4
            hints.ai_socktype = SOCK_STREAM

            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, nil, &hints, &result)

            defer {
                if result != nil {
                    freeaddrinfo(result)
                }
            }

            if status == 0, let info = result {
                var addr = info.pointee.ai_addr.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                let nameStatus = getnameinfo(
                    &addr,
                    info.pointee.ai_addrlen,
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )

                if nameStatus == 0 {
                    completion(String(cString: hostname))
                    return
                }
            }

            completion(host)
        }
    }

    func stopPinging() {
        pingTimer?.invalidate()
        pingTimer = nil
        isRunning = false
        isConnected = false
        statusMessage = "Stopped"
        latestLatency = "--"
        latestLatencyMs = nil
        averageLatency30s = 0.0
        resolvedIP = ""
    }

    private func performPing(host: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Skip if previous ping still running (avoids backlog when interval < RTT/timeout)
            if self.isPingInFlight { return }
            self.isPingInFlight = true
            defer { self.isPingInFlight = false }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            // One probe; -W is milliseconds on macOS
            process.arguments = ["-c", "1", "-W", "2000", host]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if let latency = self.parsePingOutput(output) {
                    DispatchQueue.main.async {
                        guard self.isRunning, self.host == host else { return }
                        self.latestLatencyMs = latency
                        self.latestLatency = String(format: "%.2f ms", latency)
                        self.pingResults.append(latency)

                        // Keep last 30 successful samples for graph / min-avg-max
                        if self.pingResults.count > 30 {
                            self.pingResults.removeFirst()
                        }

                        self.updateStats()
                        self.isConnected = true
                        self.statusMessage = "Connected"
                    }
                } else {
                    DispatchQueue.main.async {
                        guard self.isRunning, self.host == host else { return }
                        self.isConnected = false
                        self.statusMessage = "Timeout"
                        self.latestLatency = "✗"
                        self.latestLatencyMs = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.isRunning else { return }
                    self.statusMessage = "Error: \(error.localizedDescription)"
                    self.isConnected = false
                    self.latestLatency = "✗"
                    self.latestLatencyMs = nil
                }
            }
        }
    }

    private func parsePingOutput(_ output: String) -> Double? {
        // Look for pattern like "time=25.123 ms"
        let pattern = "time=([0-9.]+)\\s*ms"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(output.startIndex..., in: output)
            if let match = regex.firstMatch(in: output, options: [], range: range),
               let timeRange = Range(match.range(at: 1), in: output) {
                return Double(output[timeRange])
            }
        }
        return nil
    }

    private func updateStats() {
        guard !pingResults.isEmpty else {
            statsString = "---"
            averageLatency30s = 0.0
            return
        }

        let min = pingResults.min() ?? 0
        let max = pingResults.max() ?? 0
        let avg = pingResults.reduce(0, +) / Double(pingResults.count)

        statsString = String(format: "%.1f/%.1f/%.1f", min, avg, max)
        averageLatency30s = avg
    }
}
