import Foundation
import Network
import Darwin

class PingManager: NSObject, ObservableObject {
    @Published var latestLatency: String = "--"
    /// Numeric latest RTT in ms; nil when unknown / timeout / stopped.
    @Published var latestLatencyMs: Double?
    @Published var statsString: String = "--/--/--"
    @Published var statusMessage: String = "Ready"
    @Published var isConnected: Bool = false
    @Published var isRunning: Bool = false
    @Published var averageLatency30s: Double = 0.0
    /// Last 30 attempts. Nil is a timeout or probe error.
    @Published var pingResults: [Double?] = []
    @Published var resolvedIP: String = ""
    @Published var host: String
    /// Seconds between pings. Default 1. Clamped to 1...60.
    @Published var intervalSeconds: Double

    private var queue = DispatchQueue(label: "com.pingapp.ping")
    private var pingTimer: Timer?
    private var generation = 0
    private var probeActive = false
    private var probeAddress = ""

    private static let hostKey = "PingStats.host"
    private static let intervalKey = "PingStats.intervalSeconds"
    private static let oldHostKey = "PingMenuBar.host"
    private static let oldIntervalKey = "PingMenuBar.intervalSeconds"
    private static let defaultHost = "8.8.8.8"
    private static let defaultInterval: Double = 1.0
    private static let sampleWindow = 30
    static let supportedIntervals: [Double] = [1, 5, 10, 30, 60]
    private static let pingOutputRegex = try? NSRegularExpression(
        pattern: "time=([0-9.]+)\\s*ms",
        options: []
    )
    private static let hostCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-:[]"
    )

    private enum ProbeResult {
        case sample(Double)
        case timeout
        case failed(String)
    }

    override init() {
        let ud = UserDefaults.standard
        let oldUD = UserDefaults(suiteName: "com.corewaze.PingMenuBar")

        if ud.object(forKey: Self.hostKey) == nil,
           let oldHost = oldUD?.string(forKey: Self.oldHostKey), !oldHost.isEmpty
        {
            ud.set(oldHost, forKey: Self.hostKey)
        }
        if ud.object(forKey: Self.intervalKey) == nil,
           let oldInterval = oldUD?.object(forKey: Self.oldIntervalKey) as? Double, oldInterval > 0
        {
            ud.set(oldInterval, forKey: Self.intervalKey)
        }

        let savedHost = ud.string(forKey: Self.hostKey) ?? Self.defaultHost
        let savedInterval = ud.object(forKey: Self.intervalKey) as? Double
        self.host = savedHost.isEmpty ? Self.defaultHost : savedHost
        let normalizedInterval = Self.normalizedInterval(savedInterval ?? Self.defaultInterval)
        self.intervalSeconds = normalizedInterval
        super.init()
        if savedInterval != normalizedInterval {
            ud.set(normalizedInterval, forKey: Self.intervalKey)
        }
    }

    static func clampedInterval(_ value: Double) -> Double {
        min(60, max(1, value.rounded()))
    }

    static func normalizedInterval(_ value: Double) -> Double {
        let clamped = clampedInterval(value)
        return supportedIntervals.min { abs($0 - clamped) < abs($1 - clamped) } ?? defaultInterval
    }

    /// True when the string can be passed to ping without being read as a flag.
    static func isValidHost(_ raw: String) -> Bool {
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("-") else { return false }
        if let separator = host.firstIndex(of: "%") {
            guard host[host.index(after: separator)...].firstIndex(of: "%") == nil else { return false }
            let scope = host[host.index(after: separator)...]
            let scopeCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-")
            guard !scope.isEmpty, scope.unicodeScalars.allSatisfy({ scopeCharacters.contains($0) }) else { return false }
            var address = String(host[..<separator])
            if address.hasPrefix("["), address.hasSuffix("]") {
                address = String(address.dropFirst().dropLast())
            }
            guard address.contains(":"), address.unicodeScalars.allSatisfy({ hostCharacters.contains($0) }) else {
                return false
            }
            var parsedAddress = in6_addr()
            return address.withCString { inet_pton(AF_INET6, $0, &parsedAddress) == 1 }
        }
        return host.unicodeScalars.allSatisfy { hostCharacters.contains($0) }
    }

    /// Arguments for one macOS ping. IPv6 addresses get `-6`.
    static func pingArguments(_ address: String) -> [String] {
        var probe = address
        if probe.hasPrefix("["), probe.hasSuffix("]"), probe.count >= 2 {
            probe = String(probe.dropFirst().dropLast())
        }
        var args = ["-c", "1", "-W", "2000"]
        if probe.contains(":") {
            args.insert("-6", at: 0)
        }
        args.append(probe)
        return args
    }

    static func parsePingOutput(_ output: String) -> Double? {
        guard let regex = pingOutputRegex else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        if let match = regex.firstMatch(in: output, options: [], range: range),
           let timeRange = Range(match.range(at: 1), in: output) {
            return Double(output[timeRange])
        }
        return nil
    }

    /// Start (or restart) continuous pings. Uses `host` and `intervalSeconds`.
    func startPinging(host newHost: String? = nil) {
        if let newHost = newHost?.trimmingCharacters(in: .whitespacesAndNewlines), !newHost.isEmpty {
            guard Self.isValidHost(newHost) else {
                statusMessage = "Invalid host"
                return
            }
            host = newHost
            UserDefaults.standard.set(host, forKey: Self.hostKey)
        }
        guard Self.isValidHost(host) else {
            statusMessage = "Invalid host"
            return
        }

        generation += 1
        let gen = generation
        probeActive = false
        probeAddress = ""
        let target = host
        pingResults.removeAll()
        statusMessage = "Resolving..."
        latestLatency = "--"
        latestLatencyMs = nil
        averageLatency30s = 0.0
        resolvedIP = ""
        statsString = "--/--/--"
        isRunning = true
        isConnected = false

        pingTimer?.invalidate()
        pingTimer = nil

        resolveHost(target) { [weak self] resolvedHost in
            guard let self = self else { return }

            DispatchQueue.main.async {
                guard self.isRunning, self.host == target, self.generation == gen else { return }

                self.resolvedIP = resolvedHost
                self.probeAddress = resolvedHost
                self.statusMessage = "Connecting..."
                self.performPing(host: target, generation: gen, probeAddress: resolvedHost)
            }
        }
    }

    /// Update interval; persists and reschedules if currently running and idle.
    func setInterval(_ seconds: Double) {
        let normalized = Self.normalizedInterval(seconds)
        intervalSeconds = normalized
        UserDefaults.standard.set(normalized, forKey: Self.intervalKey)

        guard isRunning, !probeActive else { return }
        scheduleTimer(for: host, generation: generation)
    }

    private func scheduleTimer(for target: String, generation gen: Int) {
        pingTimer?.invalidate()

        let timer = Timer(timeInterval: intervalSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            guard self.isRunning, self.host == target, self.generation == gen, !self.probeActive else { return }
            let address = self.probeAddress.isEmpty ? target : self.probeAddress
            self.performPing(host: target, generation: gen, probeAddress: address)
        }
        RunLoop.main.add(timer, forMode: .common)
        pingTimer = timer
    }

    private func resolveHost(_ host: String, completion: @escaping (String) -> Void) {
        queue.async {
            if let address = Self.lookup(host, family: AF_INET) ?? Self.lookup(host, family: AF_INET6) {
                completion(address)
                return
            }
            completion(host)
        }
    }

    private static func lookup(_ host: String, family: Int32) -> String? {
        var hints = addrinfo()
        hints.ai_family = family
        hints.ai_socktype = SOCK_DGRAM

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else { return nil }
        defer { freeaddrinfo(info) }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let nameStatus = getnameinfo(
            info.pointee.ai_addr,
            info.pointee.ai_addrlen,
            &hostname,
            socklen_t(hostname.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard nameStatus == 0 else { return nil }
        let address = String(cString: hostname)
        return address.isEmpty ? nil : address
    }

    func stopPinging() {
        generation += 1
        probeActive = false
        probeAddress = ""
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

    private func performPing(host: String, generation gen: Int, probeAddress: String) {
        guard !probeActive else { return }
        probeActive = true
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.runPing(probeAddress)
            DispatchQueue.main.async {
                guard self.generation == gen else { return }
                self.probeActive = false
                guard self.isRunning, self.host == host else { return }
                self.apply(result)
                self.scheduleTimer(for: host, generation: gen)
            }
        }
    }

    private func runPing(_ address: String) -> ProbeResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = Self.pingArguments(address)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let watchdog = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: watchdog)
            process.waitUntilExit()
            watchdog.cancel()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if let latency = Self.parsePingOutput(output) {
                return .sample(latency)
            }
            return .timeout
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func apply(_ result: ProbeResult) {
        switch result {
        case .sample(let latency):
            latestLatencyMs = latency
            latestLatency = String(format: "%.2f ms", latency)
            append(latency)
            updateStats()
            isConnected = true
            statusMessage = "Connected"
        case .timeout:
            isConnected = false
            statusMessage = "Timeout"
            latestLatency = "✗"
            latestLatencyMs = nil
            append(nil)
        case .failed(let message):
            statusMessage = "Error: \(message)"
            isConnected = false
            latestLatency = "✗"
            latestLatencyMs = nil
            append(nil)
        }
    }

    private func append(_ sample: Double?) {
        pingResults.append(sample)
        if pingResults.count > Self.sampleWindow {
            pingResults.removeFirst()
        }
    }

    private func updateStats() {
        let samples = pingResults.compactMap { $0 }
        guard !samples.isEmpty else {
            statsString = "---"
            averageLatency30s = 0.0
            return
        }

        let minValue = samples.min() ?? 0
        let maxValue = samples.max() ?? 0
        let avg = samples.reduce(0, +) / Double(samples.count)
        statsString = String(format: "%.1f/%.1f/%.1f", minValue, avg, maxValue)
        averageLatency30s = avg
    }
}
