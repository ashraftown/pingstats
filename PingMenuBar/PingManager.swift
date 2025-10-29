import Foundation
import Network

class PingManager: NSObject, ObservableObject {
    @Published var latestLatency: String = "--"
    @Published var statsString: String = "--/--/--"
    @Published var statusMessage: String = "Ready"
    @Published var isConnected: Bool = false
    @Published var averageLatency30s: Double = 0.0
    @Published var pingResults: [Double] = []
    @Published var resolvedIP: String = ""
    private var currentHost: String?
    private var queue = DispatchQueue(label: "com.pingapp.ping")
    private var pingTimer: Timer?
    
    override init() {
        super.init()
    }
    
    func startPinging(host: String) {
        currentHost = host
        pingResults.removeAll()
        statusMessage = "Resolving..."
        latestLatency = "--"
        averageLatency30s = 0.0
        resolvedIP = ""
        
        // Invalidate existing timer
        pingTimer?.invalidate()
        
        // Resolve hostname to IP first
        resolveHost(host) { [weak self] resolvedHost in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.resolvedIP = resolvedHost
                self.statusMessage = "Connecting..."
                
                // Use simple process-based ping
                self.performPing(host: host)
                
                // Schedule repeated pings every 1 second on main run loop
                self.pingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }
                    if self.currentHost == host {
                        self.performPing(host: host)
                    } else {
                        timer.invalidate()
                    }
                }
                
                // Ensure timer runs even when menu is not open
                if let timer = self.pingTimer {
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
        }
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
                
                let result = getnameinfo(&addr, info.pointee.ai_addrlen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                
                if result == 0 {
                    let ip = String(cString: hostname)
                    completion(ip)
                    return
                }
            }
            
            // If resolution fails, use the original host
            completion(host)
        }
    }
    
    func stopPinging() {
        pingTimer?.invalidate()
        pingTimer = nil
        currentHost = nil
        statusMessage = "Stopped"
        latestLatency = "--"
        averageLatency30s = 0.0
        resolvedIP = ""
    }
    
    private func performPing(host: String) {
        queue.async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            // Ping once with 2 second timeout
            process.arguments = ["-c", "1", "-W", "2000", host]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                // Parse ping output
                if let latency = self?.parsePingOutput(output) {
                    DispatchQueue.main.async {
                        self?.latestLatency = String(format: "%.2f ms", latency)
                        self?.pingResults.append(latency)
                        
                        // Keep only last 30 results (30 seconds)
                        if self?.pingResults.count ?? 0 > 30 {
                            self?.pingResults.removeFirst()
                        }
                        
                        self?.updateStats()
                        self?.isConnected = true
                        self?.statusMessage = "Connected"
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.isConnected = false
                        self?.statusMessage = "Timeout"
                        self?.latestLatency = "✗"
                        self?.averageLatency30s = 0.0
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusMessage = "Error: \(error.localizedDescription)"
                    self?.isConnected = false
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
