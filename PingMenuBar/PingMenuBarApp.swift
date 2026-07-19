import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
struct PingMenuBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

// MARK: - Popover pin state

/// Shared UI state for the menu bar popover (pin / visibility helpers).
final class PopoverCoordinator: ObservableObject {
  @Published var isPinned = false

  fileprivate weak var appDelegate: AppDelegate?

  func togglePin() {
    isPinned.toggle()
    appDelegate?.pinStateDidChange()
  }
}

// MARK: - Open at Login

/// Manages "Open at Login" via the system Login Items API (`SMAppService`).
/// Prefer launching the copy in `/Applications` (or `~/Applications`) when enabling this.
final class LoginItemManager: ObservableObject {
  @Published private(set) var isEnabled = false
  @Published private(set) var needsApproval = false
  @Published private(set) var statusHint: String?

  init() {
    refresh()
  }

  func refresh() {
    let status = SMAppService.mainApp.status
    switch status {
    case .enabled:
      isEnabled = true
      needsApproval = false
      statusHint = nil
    case .requiresApproval:
      isEnabled = false
      needsApproval = true
      statusHint = "Allow in System Settings → General → Login Items"
    case .notFound:
      isEnabled = false
      needsApproval = false
      statusHint = "Move PingMenuBar to Applications, then try again"
    case .notRegistered:
      isEnabled = false
      needsApproval = false
      statusHint = nil
    @unknown default:
      isEnabled = false
      needsApproval = false
      statusHint = nil
    }
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        if SMAppService.mainApp.status == .enabled {
          refresh()
          return
        }
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      refresh()
    } catch {
      statusHint = error.localizedDescription
      refresh()
    }
  }

  func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}

// MARK: - App delegate / menu bar

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  var statusItem: NSStatusItem?
  var popover: NSPopover?
  var pingManager = PingManager()
  var popoverCoordinator = PopoverCoordinator()
  var cancellables = Set<AnyCancellable>()

  private var globalEventMonitor: Any?
  private var localEventMonitor: Any?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    popoverCoordinator.appDelegate = self

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem?.button {
      updateStatusBarIcon()
      button.action = #selector(togglePopover)
      button.target = self
    }

    popover = NSPopover()
    popover?.contentSize = NSSize(width: 320, height: 360)
    popover?.behavior = .applicationDefined
    popover?.delegate = self
    popover?.animates = true
    // Hide NSPopover arrow (private key; widely used for menu bar apps)
    popover?.setValue(true, forKeyPath: "shouldHideAnchor")
    popover?.contentViewController = NSHostingController(
      rootView: ContentView()
        .environmentObject(pingManager)
        .environmentObject(popoverCoordinator)
    )

    pingManager.$latestLatencyMs
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateStatusBarIcon()
      }
      .store(in: &cancellables)

    pingManager.$isConnected
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateStatusBarIcon()
      }
      .store(in: &cancellables)

    pingManager.$isRunning
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateStatusBarIcon()
      }
      .store(in: &cancellables)

    pingManager.startPinging()
  }

  @objc func togglePopover() {
    if popover?.isShown == true {
      closePopover()
    } else {
      showPopover()
    }
  }

  func showPopover() {
    guard let button = statusItem?.button, let popover = popover else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    NSApp.activate(ignoringOtherApps: true)
    updateEventMonitors()
  }

  func closePopover() {
    popover?.performClose(nil)
    removeEventMonitors()
  }

  func pinStateDidChange() {
    updateEventMonitors()
  }

  // MARK: Outside-click dismissal

  private func updateEventMonitors() {
    let shouldMonitor = (popover?.isShown == true) && !popoverCoordinator.isPinned
    if shouldMonitor {
      installEventMonitors()
    } else {
      removeEventMonitors()
    }
  }

  private func installEventMonitors() {
    removeEventMonitors()

    let handler: (NSEvent) -> Void = { [weak self] event in
      self?.handlePotentialOutsideClick(event)
    }

    globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown],
      handler: handler
    )

    localEventMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      self?.handlePotentialOutsideClick(event)
      return event
    }
  }

  private func removeEventMonitors() {
    if let globalEventMonitor {
      NSEvent.removeMonitor(globalEventMonitor)
      self.globalEventMonitor = nil
    }
    if let localEventMonitor {
      NSEvent.removeMonitor(localEventMonitor)
      self.localEventMonitor = nil
    }
  }

  private func handlePotentialOutsideClick(_ event: NSEvent) {
    guard let popover = popover, popover.isShown else { return }
    guard !popoverCoordinator.isPinned else { return }

    let clickLocation = NSEvent.mouseLocation

    if isClickInStatusItem(clickLocation) { return }
    if isClickInPopover(clickLocation) { return }
    if isClickInMenu(clickLocation) { return }

    closePopover()
  }

  private func isClickInStatusItem(_ screenPoint: NSPoint) -> Bool {
    guard let button = statusItem?.button,
          let window = button.window
    else { return false }

    let frameInWindow = button.convert(button.bounds, to: nil)
    let screenFrame = window.convertToScreen(frameInWindow)
    return screenFrame.contains(screenPoint)
  }

  private func isClickInPopover(_ screenPoint: NSPoint) -> Bool {
    guard let popoverWindow = popover?.contentViewController?.view.window else {
      return false
    }
    return popoverWindow.frame.contains(screenPoint)
  }

  private func isClickInMenu(_ screenPoint: NSPoint) -> Bool {
    for window in NSApp.windows where window.isVisible {
      if window.level == .popUpMenu || window.level == .tornOffMenu {
        if window.frame.contains(screenPoint) {
          return true
        }
      }
      let name = NSStringFromClass(type(of: window))
      if name.contains("Menu") && window.frame.contains(screenPoint) {
        return true
      }
    }
    return false
  }

  // MARK: NSPopoverDelegate

  func popoverDidClose(_ notification: Notification) {
    removeEventMonitors()
  }

  func popoverDidShow(_ notification: Notification) {
    updateEventMonitors()
  }

  // MARK: Status item icon

  func updateStatusBarIcon() {
    guard let button = statusItem?.button else { return }
    button.image = createMenuBarImage()
  }

  private func createMenuBarImage() -> NSImage {
    let color: NSColor
    let displayText: String

    if !pingManager.isRunning {
      color = NSColor.systemGray
      displayText = "--"
    } else if let ms = pingManager.latestLatencyMs {
      displayText = "\(Int(ms.rounded()))"
      if ms < 50 {
        color = NSColor.systemGreen
      } else if ms < 100 {
        color = NSColor.systemYellow
      } else if ms < 200 {
        color = NSColor.systemOrange
      } else {
        color = NSColor.systemRed
      }
    } else if pingManager.latestLatency == "✗" {
      color = NSColor.systemGray
      displayText = "✗"
    } else {
      color = NSColor.systemGray
      displayText = "…"
    }

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
      .foregroundColor: NSColor.labelColor,
    ]
    let textSize = displayText.size(withAttributes: attributes)

    let threeDigitWidth = ceil("000".size(withAttributes: attributes).width)
    let circleSize: CGFloat = 8
    let imageWidth = max(threeDigitWidth, textSize.width, circleSize)
    let size = NSSize(width: imageWidth, height: 22)
    let image = NSImage(size: size)

    image.lockFocus()

    let circleRect = NSRect(
      x: (size.width - circleSize) / 2, y: 13, width: circleSize, height: circleSize)
    let circlePath = NSBezierPath(ovalIn: circleRect)
    color.setFill()
    circlePath.fill()

    let textRect = NSRect(
      x: (size.width - textSize.width) / 2,
      y: 0,
      width: textSize.width,
      height: textSize.height
    )
    displayText.draw(in: textRect, withAttributes: attributes)

    image.unlockFocus()
    image.isTemplate = false

    return image
  }
}

// MARK: - Popup UI

struct ContentView: View {
  @EnvironmentObject var pingManager: PingManager
  @EnvironmentObject var popoverCoordinator: PopoverCoordinator
  @StateObject private var loginItems = LoginItemManager()
  @State private var hostField: String = ""
  private let intervalOptions: [Double] = [1, 2, 5, 10, 30]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("PingMenuBar")
          .font(.headline)
        Spacer()
        Button {
          popoverCoordinator.togglePin()
        } label: {
          Image(systemName: popoverCoordinator.isPinned ? "pin.fill" : "pin")
            .font(.system(size: 12, weight: .semibold))
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(popoverCoordinator.isPinned ? Color.accentColor : Color.secondary)
        .help(
          popoverCoordinator.isPinned
            ? "Unpin — close when clicking outside"
            : "Pin — keep open when clicking outside"
        )
        .accessibilityLabel(popoverCoordinator.isPinned ? "Unpin popup" : "Pin popup")
      }

      HStack {
        Text("Host:")
          .frame(width: 56, alignment: .leading)
        TextField("hostname or IP", text: $hostField)
          .textFieldStyle(.roundedBorder)
          .disabled(pingManager.isRunning)
          .onSubmit {
            guard !pingManager.isRunning else { return }
            startWithField()
          }
      }

      HStack {
        Text("Every:")
          .frame(width: 56, alignment: .leading)
        Picker("", selection: intervalBinding) {
          ForEach(intervalOptions, id: \.self) { seconds in
            Text(intervalLabel(seconds)).tag(seconds)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)

        Text(pingManager.isRunning ? "pinging…" : "paused")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 8) {
        Button(action: toggleRunning) {
          Text(pingManager.isRunning ? "Stop" : "Start")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(pingManager.isRunning ? .red : Color.accentColor)
        .disabled(
          !pingManager.isRunning
            && hostField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
      }

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Latest:")
          Text(pingManager.latestLatency)
            .fontWeight(.semibold)
            .foregroundStyle(latestColor)
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

      PingGraphView(pingResults: pingManager.pingResults)
        .frame(height: 80)

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .center) {
          Toggle("Open at Login", isOn: openAtLoginBinding)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .help("Start PingMenuBar automatically when you log in")

          if loginItems.needsApproval {
            Button("Allow…") {
              loginItems.openLoginItemsSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("macOS needs permission in System Settings → Login Items")
          }

          Spacer()

          Button("Quit PingMenuBar") {
            NSApp.terminate(nil)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .tint(.secondary)
        }

        if let hint = loginItems.statusHint {
          Text(hint)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding()
    .frame(width: 300)
    .onAppear {
      if hostField.isEmpty {
        hostField = pingManager.host
      }
      loginItems.refresh()
    }
  }

  private var openAtLoginBinding: Binding<Bool> {
    Binding(
      get: { loginItems.isEnabled || loginItems.needsApproval },
      set: { loginItems.setEnabled($0) }
    )
  }

  private var intervalBinding: Binding<Double> {
    Binding(
      get: { pingManager.intervalSeconds },
      set: { pingManager.setInterval($0) }
    )
  }

  private var latestColor: Color {
    if pingManager.latestLatency == "--" {
      return .gray
    }
    if pingManager.latestLatency == "✗" {
      return .red
    }
    return .green
  }

  private func intervalLabel(_ seconds: Double) -> String {
    if seconds == 1 {
      return "1 second"
    }
    return "\(Int(seconds)) seconds"
  }

  private func toggleRunning() {
    if pingManager.isRunning {
      pingManager.stopPinging()
    } else {
      startWithField()
    }
  }

  private func startWithField() {
    let trimmed = hostField.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    pingManager.startPinging(host: trimmed)
  }
}

struct PingGraphView: View {
  let pingResults: [Double]

  var body: some View {
    HStack(spacing: 4) {
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

      GeometryReader { geometry in
        HStack(alignment: .bottom, spacing: 2) {
          ForEach(Array(pingResults.enumerated()), id: \.offset) { _, latency in
            Rectangle()
              .fill(colorForLatency(latency))
              .frame(
                width: max(
                  1,
                  (geometry.size.width - CGFloat(pingResults.count - 1) * 2)
                    / CGFloat(max(pingResults.count, 1))
                )
              )
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
    guard maxLatency > 0 else { return 0 }
    let ratio = latency / maxLatency
    return max(2, ratio * maxHeight)
  }
}
