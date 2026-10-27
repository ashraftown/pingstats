import Foundation
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

    /// Probes run concurrently so a restarted probe never waits behind the one
    /// it replaced. `probeActive` still keeps a single probe per schedule.
    private var queue = DispatchQueue(label: "com.pingapp.ping", attributes: .concurrent)
    /// DNS lookups run here so a slow resolver never delays probes waiting on
    /// the shared ping queue.
    private let resolveQueue = DispatchQueue(label: "com.pingapp.resolve")
    private var pingTimer: Timer?
    private var generation = 0
    private var probeActive = false
    private var probeAddress = ""
    /// Identifies the probe in flight, so an interval change can abandon just
    /// that probe without touching session-wide DNS work.
    private var probeToken = 0
    /// Failed probes since the last reply. A few in a row trigger a fresh DNS
    /// lookup, so a stale address or a changed network recovers on its own.
    private var consecutiveFailures = 0
    /// True while one DNS lookup or retry is queued. A failing link must not
    /// pile up lookups, and a new session starts with a clean slate.
    private var resolvePending = false

    /// Delay between DNS retries after a failed resolve.
    private static let resolveRetrySeconds: TimeInterval = 3
    /// Failed probes before the address is resolved again.
    private static let failuresBeforeResolve = 3

    private static let hostKey = "PingStats.host"
    private static let intervalKey = "PingStats.intervalSeconds"
    private static let oldHostKey = "PingMenuBar.host"
    private static let oldIntervalKey = "PingMenuBar.intervalSeconds"
    private static let defaultHost = "8.8.8.8"
    private static let defaultInterval: Double = 1.0
    private static let sampleWindow = 30
    static let supportedIntervals: [Double] = [1, 5, 10, 30, 60]
    private static let hostCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-:[]"
    )

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

    /// True when the string is a host name or IP address that can be probed.
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

    static func isIPAddress(_ raw: String) -> Bool {
        var address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scope = address.firstIndex(of: "%") {
            address = String(address[..<scope])
        }
        if address.hasPrefix("["), address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        if address.contains(":") {
            var parsed = in6_addr()
            return address.withCString { inet_pton(AF_INET6, $0, &parsed) == 1 }
        }
        var parsed = in_addr()
        return address.withCString { inet_pton(AF_INET, $0, &parsed) == 1 }
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
        consecutiveFailures = 0
        resolvePending = false
        pingTimer?.invalidate()
        pingTimer = nil
        pingResults.removeAll()
        statusMessage = "Resolving..."
        latestLatency = "--"
        latestLatencyMs = nil
        averageLatency30s = 0.0
        resolvedIP = ""
        statsString = "--/--/--"
        isRunning = true
        isConnected = false

        let target = host
        attemptResolve(for: target, generation: gen, startProbeOnSuccess: true)
    }

    /// Resolve `target`, then start probing it. If DNS does not answer, retry
    /// every `resolveRetrySeconds` until it does (or the session changes), so
    /// monitoring resumes on its own after an offline start. IP literals skip
    /// DNS. IPv4 is preferred, IPv6 is used when a name has no A record.
    ///
    /// Only one lookup or retry runs per session. Failed probes ask for a
    /// lookup again, and without the gate every batch would start its own retry
    /// chain during an outage.
    private func attemptResolve(
        for target: String,
        generation gen: Int,
        startProbeOnSuccess: Bool,
        retryAfter delay: TimeInterval? = nil
    ) {
        if delay == nil, Self.isIPAddress(target) {
            accept(address: target, host: target, generation: gen, startProbeOnSuccess: startProbeOnSuccess)
            return
        }

        guard !resolvePending else { return }
        resolvePending = true

        let lookup = { [weak self] in
            guard let self = self else { return }
            let address = Self.lookupIPv4or6(target)

            DispatchQueue.main.async {
                guard self.generation == gen else { return }
                self.resolvePending = false
                guard self.isRunning, self.host == target else { return }

                guard let address else {
                    self.statusMessage = "Waiting for DNS..."
                    self.attemptResolve(
                        for: target,
                        generation: gen,
                        startProbeOnSuccess: startProbeOnSuccess,
                        retryAfter: Self.resolveRetrySeconds
                    )
                    return
                }

                self.accept(address: address, host: target, generation: gen, startProbeOnSuccess: startProbeOnSuccess)
            }
        }

        if let delay {
            resolveQueue.asyncAfter(deadline: .now() + delay, execute: lookup)
        } else {
            resolveQueue.async(execute: lookup)
        }
    }

    private func accept(address: String, host target: String, generation gen: Int, startProbeOnSuccess: Bool) {
        resolvedIP = address
        probeAddress = address
        guard startProbeOnSuccess else { return }
        statusMessage = "Connecting..."
        performPing(host: target, generation: gen, probeAddress: address)
    }

    /// Update interval; persists and restarts the timer if currently running.
    /// A probe in flight was sized for the old interval, so it is abandoned and
    /// one probe with the new timeout starts at once.
    func setInterval(_ seconds: Double) {
        let normalized = Self.normalizedInterval(seconds)
        intervalSeconds = normalized
        UserDefaults.standard.set(normalized, forKey: Self.intervalKey)

        guard isRunning, !probeAddress.isEmpty else { return }
        if probeActive {
            probeActive = false
            performPing(host: host, generation: generation, probeAddress: probeAddress)
        }
        restartTimer(for: host, generation: generation)
    }

    /// One repeating timer keeps the sample cadence steady. A tick that lands
    /// while a probe is still in flight is skipped.
    private func ensureTimer(for target: String, generation gen: Int) {
        guard pingTimer == nil else { return }

        let timer = Timer(timeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isRunning, self.host == target, self.generation == gen,
                  !self.probeActive, !self.probeAddress.isEmpty else { return }
            self.performPing(host: target, generation: gen, probeAddress: self.probeAddress)
        }
        RunLoop.main.add(timer, forMode: .common)
        pingTimer = timer
    }

    private func restartTimer(for target: String, generation gen: Int) {
        pingTimer?.invalidate()
        pingTimer = nil
        ensureTimer(for: target, generation: gen)
    }

    /// Resolve a target to an address string via DNS, preferring IPv4.
    /// Returns nil when DNS does not answer.
    private static func lookupIPv4or6(_ target: String) -> String? {
        lookup(target, family: AF_INET) ?? lookup(target, family: AF_INET6)
    }

    /// Resolve one address family; returns nil when DNS does not answer.
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
        consecutiveFailures = 0
        resolvePending = false
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
        probeToken += 1
        let token = probeToken
        let timeout = PingProbe.timeout(forInterval: intervalSeconds)
        queue.async { [weak self] in
            guard let self else { return }
            let result = PingProbe.run(address: probeAddress, timeout: timeout)
            DispatchQueue.main.async {
                guard self.generation == gen, self.probeToken == token else { return }
                self.probeActive = false
                guard self.isRunning, self.host == host else { return }
                self.apply(result)
                self.ensureTimer(for: host, generation: gen)
            }
        }
    }

    private func apply(_ result: PingProbeResult) {
        switch result {
        case .latency(let latency):
            consecutiveFailures = 0
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
            handleProbeFailure()
        case .failure(let message):
            statusMessage = "Error: \(message)"
            isConnected = false
            latestLatency = "✗"
            latestLatencyMs = nil
            append(nil)
            handleProbeFailure()
        }
    }

    /// After a few failed probes in a row, resolve again. A Wi-Fi change or a
    /// bad address family choice then recovers without a manual restart.
    private func handleProbeFailure() {
        consecutiveFailures += 1
        guard consecutiveFailures >= Self.failuresBeforeResolve else { return }
        consecutiveFailures = 0
        attemptResolve(for: host, generation: generation, startProbeOnSuccess: false)
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
