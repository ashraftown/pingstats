import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
struct PingStatsApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    // SwiftUI requires at least one Scene. Do **not** use `Settings { … }` —
    // that creates a real “PingStats Settings” window on launch.
    // A never-inserted MenuBarExtra satisfies the protocol without UI;
    // the actual status item + popover are owned by AppDelegate.
    MenuBarExtra(isInserted: .constant(false)) {
      EmptyView()
    } label: {
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
      statusHint = "Move PingStats to Applications, then try again"
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

    // Menu-bar-only app: dismiss any Scene-created windows (e.g. leftover Settings).
    for window in NSApp.windows {
      window.close()
    }

    popoverCoordinator.appDelegate = self

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem?.button {
      updateStatusBarIcon()
      button.action = #selector(togglePopover)
      button.target = self
    }

    popover = NSPopover()
    popover?.behavior = .applicationDefined
    popover?.delegate = self
    popover?.animates = true
    // Hide NSPopover arrow (private key; widely used for menu bar apps)
    popover?.setValue(true, forKeyPath: "shouldHideAnchor")

    let hostingController = NSHostingController(
      rootView: ContentView()
        .environmentObject(pingManager)
        .environmentObject(popoverCoordinator)
    )
    popover?.contentViewController = hostingController
    let fittingSize = hostingController.view.fittingSize
    popover?.contentSize = fittingSize.width > 0 && fittingSize.height > 0
      ? fittingSize
      : NSSize(width: 340, height: 620)

    pingManager.objectWillChange
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
      switch LatencyTier.tier(ms) {
      case .green:
        color = NSColor.systemGreen
      case .yellow:
        color = NSColor.systemYellow
      case .red:
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

// MARK: - Design tokens

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1
    )
  }
}

enum LatencyTier {
  case green
  case yellow
  case red

  static func tier(_ ms: Double) -> LatencyTier {
    if ms < 60 { return .green }
    if ms <= 120 { return .yellow }
    return .red
  }

  var color: Color {
    switch self {
    case .green: return Color(hex: 0x34D399)
    case .yellow: return Color(hex: 0xF5A623)
    case .red: return Color(hex: 0xF0625F)
    }
  }
}

enum PopupState: Equatable {
  case stopped
  case resolving
  case connected
  case timeout

  var pillText: String {
    switch self {
    case .stopped: return "stopped"
    case .resolving: return "resolving"
    case .connected: return "connected"
    case .timeout: return "timeout"
    }
  }

  var pillFg: Color {
    switch self {
    case .connected: return Color(hex: 0x34D399)
    case .timeout: return Color(hex: 0xF0958F)
    case .stopped, .resolving: return Color.secondary
    }
  }

  var pillBg: Color {
    switch self {
    case .connected: return Color(hex: 0x34D399).opacity(0.12)
    case .timeout: return Color(hex: 0xF0625F).opacity(0.12)
    case .stopped, .resolving: return Color.primary.opacity(0.1)
    }
  }

  var pillBorder: Color {
    switch self {
    case .connected: return Color(hex: 0x34D399).opacity(0.28)
    case .timeout: return Color(hex: 0xF0625F).opacity(0.28)
    case .stopped, .resolving: return Color.primary.opacity(0.12)
    }
  }

  var dotColor: Color {
    switch self {
    case .connected: return Color(hex: 0x34D399)
    case .timeout: return Color(hex: 0xF0625F)
    case .stopped, .resolving: return Color.secondary
    }
  }

  var dotPulses: Bool { self == .connected }

  var heroCaption: String {
    switch self {
    case .connected: return "latest ping"
    case .resolving: return "resolving…"
    case .stopped: return "not monitoring"
    case .timeout: return "timeout"
    }
  }

  var heroFallbackNumber: String {
    switch self {
    case .stopped, .resolving: return "--"
    case .timeout: return "✗"
    case .connected: return "--"
    }
  }
}

// MARK: - Popup UI

struct ContentView: View {
  @EnvironmentObject var pingManager: PingManager
  @EnvironmentObject var popoverCoordinator: PopoverCoordinator
  @StateObject private var loginItems = LoginItemManager()
  @State private var hostField = ""
  @State private var showQuitConfirm = false
  @State private var intervalMenuTarget = IntervalMenuTarget()
  private let intervalOptions: [Double] = [1, 5, 10, 30]

  private var state: PopupState {
    if !pingManager.isRunning { return .stopped }
    if pingManager.isConnected { return .connected }
    if pingManager.latestLatency == "✗" { return .timeout }
    return .resolving
  }

  private var hostEmpty: Bool {
    hostField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      headerRow
      hero
      PingChartView(pingResults: pingManager.pingResults, strokeColor: chartColor)
      statsRow
      statusRow
      hostBlock
      intervalBlock
      toggleButton
      footerOrConfirm
        .animation(.easeInOut(duration: 0.15), value: showQuitConfirm)
    }
    .padding(20)
    .frame(width: 340)
    .onAppear {
      if hostField.isEmpty {
        hostField = pingManager.host
      }
      loginItems.refresh()
    }
  }

  // MARK: Header

  private var headerRow: some View {
    HStack {
      HStack(spacing: 8) {
        PulsingDot(color: state.dotColor, isPulsing: state.dotPulses)
          .frame(width: 8, height: 8)
        Text("PingStats")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Color.primary)
      }
      Spacer()
      Button {
        popoverCoordinator.togglePin()
      } label: {
        Image(systemName: "pin")
          .font(.system(size: 14))
          .foregroundStyle(
            popoverCoordinator.isPinned ? Color(hex: 0x0B0C0F) : Color(hex: 0x4C8DFF)
          )
          .rotationEffect(.degrees(popoverCoordinator.isPinned ? 0 : 35))
          .frame(width: 26, height: 26)
          .background(
            popoverCoordinator.isPinned ? Color(hex: 0x4C8DFF) : Color(hex: 0x4C8DFF).opacity(0.12)
          )
          .clipShape(RoundedRectangle(cornerRadius: 7))
          .overlay(
            RoundedRectangle(cornerRadius: 7)
              .stroke(
                Color(hex: 0x4C8DFF).opacity(popoverCoordinator.isPinned ? 1 : 0.28),
                lineWidth: 1
              )
          )
      }
      .buttonStyle(.plain)
      .animation(.easeOut(duration: 0.2), value: popoverCoordinator.isPinned)
      .help(
        popoverCoordinator.isPinned
          ? "Unpin — close when clicking outside"
          : "Pin — keep open when clicking outside"
      )
      .accessibilityLabel(popoverCoordinator.isPinned ? "Unpin popup" : "Pin popup")
    }
  }

  // MARK: Hero

  private var hero: some View {
    VStack(spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(heroNumber)
          .font(.system(size: 38, weight: .medium, design: .monospaced))
          .foregroundStyle(heroColor)
        if state == .connected {
          Text("ms")
            .font(.system(size: 16, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.secondary)
        }
      }
      Text(state.heroCaption)
        .font(.system(size: 12))
        .foregroundStyle(Color.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 2)
  }

  private var heroNumber: String {
    if state == .connected, let ms = pingManager.latestLatencyMs {
      return "\(Int(ms.rounded()))"
    }
    return state.heroFallbackNumber
  }

  private var heroColor: Color {
    switch state {
    case .connected:
      if let ms = pingManager.latestLatencyMs {
        return LatencyTier.tier(ms).color
      }
      return Color(hex: 0x34D399)
    case .timeout:
      return Color(hex: 0xF0625F)
    case .stopped, .resolving:
      return Color.secondary
    }
  }

  private var chartColor: Color {
    switch state {
    case .connected:
      if let ms = pingManager.latestLatencyMs {
        return LatencyTier.tier(ms).color
      }
      return Color(hex: 0x34D399)
    case .stopped, .resolving, .timeout:
      return Color.secondary
    }
  }

  // MARK: Stats

  private var statsRow: some View {
    VStack(spacing: 0) {
      Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
      HStack(spacing: 0) {
        statCell(statsValues.min, "min")
        statDivider
        statCell(statsValues.avg, "avg")
        statDivider
        statCell(statsValues.max, "max")
      }
      .padding(.vertical, 12)
      Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
    }
  }

  private var statDivider: some View {
    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
  }

  private func statCell(_ value: String, _ label: String) -> some View {
    VStack(spacing: 3) {
      Text(value)
        .font(.system(size: 15, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.primary)
      Text(label)
        .font(.system(size: 10))
        .foregroundStyle(Color.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  private var statsValues: (min: String, avg: String, max: String) {
    let results = pingManager.pingResults
    guard !results.isEmpty else { return ("--", "--", "--") }
    let min = results.min() ?? 0
    let max = results.max() ?? 0
    let avg = results.reduce(0, +) / Double(results.count)
    return ("\(Int(min.rounded()))", "\(Int(avg.rounded()))", "\(Int(max.rounded()))")
  }

  // MARK: Status pill

  private var statusRow: some View {
    HStack {
      Text("status")
        .font(.system(size: 12))
        .foregroundStyle(Color.secondary)
      Spacer()
      HStack(spacing: 5) {
        Circle().fill(state.dotColor).frame(width: 5, height: 5)
        Text(state.pillText)
          .font(.system(size: 11, weight: .medium))
      }
      .foregroundStyle(state.pillFg)
      .padding(.horizontal, 9)
      .padding(.vertical, 2)
      .background(state.pillBg)
      .clipShape(Capsule())
      .overlay(Capsule().stroke(state.pillBorder, lineWidth: 1))
      .animation(.easeOut(duration: 0.2), value: state.pillText)
    }
  }

  // MARK: Host

  private var hostBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("host")
        .font(.system(size: 11))
        .foregroundStyle(Color.secondary)
      TextField("hostname or IP", text: $hostField)
        .textFieldStyle(.plain)
        .font(.system(size: 13, design: .monospaced))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .disabled(pingManager.isRunning)
        .onSubmit {
          guard !pingManager.isRunning else { return }
          startWithField()
        }
      resolveNote
    }
  }

  private var resolveNote: some View {
    let text: Text
    let color: Color
    if !pingManager.resolvedIP.isEmpty {
      text = Text("resolves to ") + Text(pingManager.resolvedIP)
      color = Color.secondary
    } else if state == .resolving {
      text = Text("resolving…")
      color = Color.secondary
    } else {
      text = Text(" ")
      color = Color.secondary
    }
    return text
      .font(.system(size: 10, design: .monospaced))
      .foregroundStyle(color)
      .opacity(!pingManager.resolvedIP.isEmpty || state == .resolving ? 1 : 0)
  }

  // MARK: Interval

  private var intervalBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("check every")
        .font(.system(size: 11))
        .foregroundStyle(Color.secondary)
      Button(action: presentIntervalMenu) {
        HStack(spacing: 8) {
          Text(intervalLabel(pingManager.intervalSeconds))
            .font(.system(size: 13, design: .monospaced))
          Spacer()
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 11))
            .foregroundStyle(Color.secondary)
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
    }
  }

  // MARK: Toggle

  private var toggleButton: some View {
    Button(action: toggleRunning) {
      HStack(spacing: 6) {
        Image(systemName: pingManager.isRunning ? "stop.fill" : "play.fill")
          .font(.system(size: 14))
        Text(pingManager.isRunning ? "stop monitoring" : "start monitoring")
          .font(.system(size: 13, weight: .medium))
      }
      .foregroundStyle(toggleFg)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 11)
      .background(toggleBg)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(toggleBorder, lineWidth: 1))
      .contentShape(RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
    .disabled(!pingManager.isRunning && hostEmpty)
    .opacity(!pingManager.isRunning && hostEmpty ? 0.4 : 1)
    .animation(.easeOut(duration: 0.2), value: pingManager.isRunning)
  }

  private var toggleFg: Color {
    pingManager.isRunning ? Color(hex: 0xF0958F) : Color(hex: 0x34D399)
  }

  private var toggleBg: Color {
    pingManager.isRunning
      ? Color(hex: 0xF0625F).opacity(0.12)
      : Color(hex: 0x34D399).opacity(0.12)
  }

  private var toggleBorder: Color {
    pingManager.isRunning
      ? Color(hex: 0xF0625F).opacity(0.28)
      : Color(hex: 0x34D399).opacity(0.28)
  }

  // MARK: Footer / quit confirm

  @ViewBuilder
  private var footerOrConfirm: some View {
    if showQuitConfirm {
      HStack {
        Text("quit pingstats?")
          .font(.system(size: 12))
          .foregroundStyle(Color.secondary)
        Spacer()
        Button("cancel") {
          showQuitConfirm = false
        }
        .buttonStyle(FooterButtonStyle())
        Button("quit") {
          NSApp.terminate(nil)
        }
        .buttonStyle(
          FooterButtonStyle(
            fg: Color(hex: 0xF0958F),
            bg: Color(hex: 0xF0625F).opacity(0.12),
            border: Color(hex: 0xF0625F).opacity(0.28)
          )
        )
      }
      .transition(.opacity)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          HStack(spacing: 7) {
          Toggle("open at login", isOn: openAtLoginBinding)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
          Text("open at login")
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary)
        }
        Spacer()
          Button {
            showQuitConfirm = true
          } label: {
            HStack(spacing: 5) {
              Image(systemName: "power")
                .font(.system(size: 13))
              Text("quit")
                .font(.system(size: 12))
            }
          }
          .buttonStyle(FooterButtonStyle())
        }

        if loginItems.needsApproval {
          HStack {
            Button("Allow…") {
              loginItems.openLoginItemsSettings()
            }
            .buttonStyle(FooterButtonStyle())
            if let hint = loginItems.statusHint {
              Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
            }
          }
        } else if let hint = loginItems.statusHint {
          Text(hint)
            .font(.system(size: 10))
            .foregroundStyle(Color.secondary)
        }
      }
    }
  }

  // MARK: Bindings / actions

  private var openAtLoginBinding: Binding<Bool> {
    Binding(
      get: { loginItems.isEnabled || loginItems.needsApproval },
      set: { loginItems.setEnabled($0) }
    )
  }

  private func intervalLabel(_ seconds: Double) -> String {
    if seconds == 1 {
      return "1 second"
    }
    return "\(Int(seconds)) seconds"
  }

  private func presentIntervalMenu() {
    intervalMenuTarget.onSelect = { [pingManager] seconds in
      pingManager.setInterval(seconds)
    }
    let menu = NSMenu()
    for seconds in intervalOptions {
      let item = NSMenuItem(
        title: intervalLabel(seconds),
        action: #selector(IntervalMenuTarget.select(_:)),
        keyEquivalent: ""
      )
      item.target = intervalMenuTarget
      item.tag = Int(seconds)
      item.state = seconds == pingManager.intervalSeconds ? .on : .off
      menu.addItem(item)
    }
    let mouse = NSEvent.mouseLocation
    let point = NSPoint(x: mouse.x, y: mouse.y - 12)
    menu.popUp(positioning: nil, at: point, in: nil)
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

struct FooterButtonStyle: ButtonStyle {
  var fg: Color = .secondary
  var bg: Color = .clear
  var border: Color = Color.primary.opacity(0.12)

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12))
      .foregroundStyle(fg)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(bg)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
      .contentShape(RoundedRectangle(cornerRadius: 8))
      .opacity(configuration.isPressed ? 0.85 : 1)
  }
}

struct PulsingDot: View {
  let color: Color
  let isPulsing: Bool

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.05, paused: !isPulsing)) { context in
      Circle()
        .fill(color)
        .opacity(isPulsing ? pulseOpacity(context.date) : 1)
    }
  }

  private func pulseOpacity(_ date: Date) -> Double {
    let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2)
    return 0.35 + 0.65 * abs(cos(.pi * phase))
  }
}

// MARK: - Interval field helpers

/// NSObject target for the interval menu items; keeps a strong reference to
/// the selection closure.
private final class IntervalMenuTarget: NSObject {
  var onSelect: ((Double) -> Void)?

  @objc func select(_ sender: NSMenuItem) {
    onSelect?(Double(sender.tag))
  }
}

// MARK: - Ping chart

/// Live line/area chart of the last 30 samples with a dynamic Y axis and a
/// 550ms slide-in on each new sample. Coordinate math mirrors the mock.
struct PingChartView: View {
  let pingResults: [Double]
  let strokeColor: Color

  @State private var settled: [Double] = []
  @State private var display: [Double] = []
  @State private var slideProgress: CGFloat = 0

  private let slideDuration = 0.55
  private static let marginLeft: CGFloat = 28

  var body: some View {
    GeometryReader { geo in
      let plotWidth = geo.size.width - Self.marginLeft
      let count = max(settled.count, 2)
      let stepX = plotWidth / CGFloat(count - 1)
      let chart = display.isEmpty ? settled : display
      let axisMax = Self.axisMax(chart)
      let baselineY = geo.size.height * (40 / 54)
      let topY = geo.size.height * (2 / 54)

      ZStack(alignment: .topLeading) {
        gridlines(width: geo.size.width, topY: topY, baselineY: baselineY)
        axisLabels(axisMax: axisMax, topY: topY, baselineY: baselineY)

        ZStack(alignment: .topLeading) {
          Self.areaPath(
            chart,
            stepX: stepX,
            axisMax: axisMax,
            topY: topY,
            baselineY: baselineY,
            bottomY: geo.size.height
          )
          .fill(strokeColor.opacity(0.12))

          Self.linePath(chart, stepX: stepX, axisMax: axisMax, topY: topY, baselineY: baselineY)
            .stroke(
              strokeColor,
              style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

          ForEach(Array(chart.enumerated()), id: \.offset) { index, value in
            if value > 120 {
              Circle()
                .fill(Color(hex: 0xF0625F))
                .frame(width: 6, height: 6)
                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                .position(
                  x: Self.marginLeft + CGFloat(index) * stepX,
                  y: Self.y(value, axisMax: axisMax, topY: topY, baselineY: baselineY)
                )
            }
          }
        }
        .offset(x: -slideProgress * stepX)
        .clipShape(PlotClip(marginLeft: Self.marginLeft))
      }
    }
    .frame(height: 64)
    .onChange(of: pingResults) { newValues in
      sync(newValues)
    }
  }

  private func sync(_ newValues: [Double]) {
    if newValues == settled { return }
    if newValues.isEmpty {
      settled = []
      display = []
      slideProgress = 0
      return
    }
    // Steady-state slide only once the 30-sample window is full and a new
    // sample has shifted in (count stays 30 because the manager drops the head).
    let shiftedIn =
      settled.count == 30
      && newValues.count == 30
      && newValues.dropLast() == settled.dropFirst()
    guard shiftedIn, let last = newValues.last else {
      settled = newValues
      display = []
      slideProgress = 0
      return
    }
    let extended = settled + [last]
    display = extended
    slideProgress = 0
    withAnimation(.easeOut(duration: slideDuration)) {
      slideProgress = 1
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + slideDuration + 0.05) {
      settled = newValues
      display = []
      slideProgress = 0
    }
  }

  private func gridlines(width: CGFloat, topY: CGFloat, baselineY: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      dashedLine(y: topY, width: width, opacity: 0.08)
      dashedLine(y: (topY + baselineY) / 2, width: width, opacity: 0.08)
      Rectangle()
        .fill(Color.primary.opacity(0.12))
        .frame(width: width - Self.marginLeft, height: 1)
        .offset(x: Self.marginLeft, y: baselineY)
    }
  }

  private func dashedLine(y: CGFloat, width: CGFloat, opacity: Double) -> some View {
    Path { path in
      path.move(to: CGPoint(x: Self.marginLeft, y: y))
      path.addLine(to: CGPoint(x: width, y: y))
    }
    .stroke(Color.primary.opacity(opacity), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
  }

  private func axisLabels(axisMax: Double, topY: CGFloat, baselineY: CGFloat) -> some View {
    let midY = (topY + baselineY) / 2
    return ZStack(alignment: .topLeading) {
      Text("\(Int(axisMax))")
        .font(.system(size: 8.5, design: .monospaced))
        .foregroundStyle(Color.secondary)
        .position(x: 22, y: topY + 5)
      Text("\(Int(axisMax / 2))")
        .font(.system(size: 8.5, design: .monospaced))
        .foregroundStyle(Color.secondary)
        .position(x: 22, y: midY + 5)
      Text("0")
        .font(.system(size: 8.5, design: .monospaced))
        .foregroundStyle(Color.secondary)
        .position(x: 22, y: baselineY + 5)
    }
  }

  /// Clips the sliding chart layer to the plot area (right of the Y-axis
  /// labels) so the line never overflows the card while animating.
  private struct PlotClip: Shape {
    var marginLeft: CGFloat

    func path(in rect: CGRect) -> Path {
      var path = Path()
      path.addRect(
        CGRect(x: marginLeft, y: 0, width: max(0, rect.width - marginLeft), height: rect.height)
      )
      return path
    }
  }

  private static func axisMax(_ values: [Double]) -> Double {
    guard let maxValue = values.max(), maxValue > 0 else { return 100 }
    return max(100, ceil(maxValue / 50) * 50)
  }

  private static func y(_ value: Double, axisMax: Double, topY: CGFloat, baselineY: CGFloat) -> CGFloat {
    let fraction = min(1, max(0, value / axisMax))
    return baselineY - CGFloat(fraction) * (baselineY - topY)
  }

  private static func linePath(
    _ values: [Double],
    stepX: CGFloat,
    axisMax: Double,
    topY: CGFloat,
    baselineY: CGFloat
  ) -> Path {
    Path { path in
      for (index, value) in values.enumerated() {
        let point = CGPoint(
          x: marginLeft + CGFloat(index) * stepX,
          y: y(value, axisMax: axisMax, topY: topY, baselineY: baselineY)
        )
        if index == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
    }
  }

  private static func areaPath(
    _ values: [Double],
    stepX: CGFloat,
    axisMax: Double,
    topY: CGFloat,
    baselineY: CGFloat,
    bottomY: CGFloat
  ) -> Path {
    Path { path in
      let lastIndex = values.count - 1
      guard lastIndex >= 0 else { return }
      path.move(to: CGPoint(x: marginLeft, y: bottomY))
      for (index, value) in values.enumerated() {
        path.addLine(
          to: CGPoint(
            x: marginLeft + CGFloat(index) * stepX,
            y: y(value, axisMax: axisMax, topY: topY, baselineY: baselineY)
          )
        )
      }
      path.addLine(to: CGPoint(x: marginLeft + CGFloat(lastIndex) * stepX, y: bottomY))
      path.closeSubpath()
    }
  }
}
