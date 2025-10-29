import SwiftUI

struct ContentView: View {
    @EnvironmentObject var pingManager: PingManager
    @State private var hostname: String = "8.8.8.8"
    @State private var isRunning: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Host:")
                TextField("Enter hostname", text: $hostname)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRunning)
            }
            
            HStack(spacing: 8) {
                Button(action: {
                    if isRunning {
                        pingManager.stopPinging()
                        isRunning = false
                    } else {
                        pingManager.startPinging(host: hostname)
                        isRunning = true
                    }
                }) {
                    Text(isRunning ? "Stop" : "Ping")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.gray)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Latest:")
                    Text(pingManager.latestLatency)
                        .fontWeight(.semibold)
                        .foregroundStyle(pingManager.latestLatency == "--" ? .gray : .green)
                }
                
                HStack {
                    Text("Min/Avg/Max:")
                    Text(pingManager.statsString)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                
                if !pingManager.resolvedIP.isEmpty {
                    HStack {
                        Text("IP:")
                        Text(pingManager.resolvedIP)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack {
                    Text("Status:")
                    Text(pingManager.statusMessage)
                        .fontWeight(.semibold)
                        .foregroundStyle(pingManager.isConnected ? .green : .red)
                }
            }
            .font(.system(.body, design: .monospaced))
            
            Divider()
            
            // Ping history graph
            PingGraphView(pingResults: pingManager.pingResults)
                .frame(height: 80)
        }
        .padding()
        .onDisappear {
            if isRunning {
                pingManager.stopPinging()
            }
        }
    }
}

struct PingGraphView: View {
    let pingResults: [Double]
    
    var body: some View {
        HStack(spacing: 4) {
            // Y-axis labels
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(maxLatency))ms")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(maxLatency / 2))ms")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Spacer()
                Text("0ms")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .frame(width: 30)
            
            // Graph
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(pingResults.enumerated()), id: \.offset) { index, latency in
                        Rectangle()
                            .fill(colorForLatency(latency))
                            .frame(width: max(1, (geometry.size.width - CGFloat(pingResults.count - 1) * 2) / CGFloat(max(pingResults.count, 1))))
                            .frame(height: heightForLatency(latency, maxHeight: geometry.size.height))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
        }
    }
    
    private var maxLatency: Double {
        pingResults.max() ?? 100
    }
    
    private func colorForLatency(_ ms: Double) -> Color {
        if ms < 50 {
            return .green
        } else if ms < 100 {
            return .yellow
        } else if ms < 200 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func heightForLatency(_ latency: Double, maxHeight: CGFloat) -> CGFloat {
        guard maxLatency > 0 else {
            return 0
        }
        // Scale to fit, with minimum height of 2px
        let ratio = latency / maxLatency
        return max(2, ratio * maxHeight)
    }
}

#Preview {
    ContentView()
        .environmentObject(PingManager())
}
