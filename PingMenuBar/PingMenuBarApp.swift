import Combine
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

class AppDelegate: NSObject, NSApplicationDelegate {
  var statusItem: NSStatusItem?
  var popover: NSPopover?
  var pingManager = PingManager()
  var cancellables = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Create status bar item
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem?.button {
      updateStatusBarIcon()
      button.action = #selector(togglePopover)
      button.target = self
    }

    // Create popover
    popover = NSPopover()
    popover?.contentSize = NSSize(width: 300, height: 250)
    popover?.behavior = .transient
    popover?.contentViewController = NSHostingController(
      rootView: ContentView().environmentObject(pingManager)
    )

    // Observe changes to update icon
    pingManager.$averageLatency30s
      .sink { [weak self] _ in
        self?.updateStatusBarIcon()
      }
      .store(in: &cancellables)

    pingManager.$isConnected
      .sink { [weak self] _ in
        self?.updateStatusBarIcon()
      }
      .store(in: &cancellables)

    // Start pinging automatically on launch
    pingManager.startPinging(host: "8.8.8.8")
  }

  @objc func togglePopover() {
    if let button = statusItem?.button {
      if popover?.isShown == true {
        popover?.performClose(nil)
      } else {
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      }
    }
  }

  func updateStatusBarIcon() {
    guard let button = statusItem?.button else { return }
    button.image = createMenuBarImage()
  }

  private func createMenuBarImage() -> NSImage {
    // Determine color based on latency
    let color: NSColor
    let displayText: String

    let averageLatency = pingManager.averageLatency30s
    let isConnected = pingManager.isConnected

    if !isConnected || averageLatency == 0.0 {
      color = NSColor.systemGray
      displayText = "--"
    } else {
      let ms = averageLatency
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
    }

    // Calculate text size first to determine image width - use smaller, condensed font
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
      .foregroundColor: NSColor.labelColor,
    ]
    let textSize = displayText.size(withAttributes: attributes)

    // Make image width match text width (or slightly wider for circle) - no padding
    let circleSize: CGFloat = 8
    let imageWidth = max(textSize.width, circleSize)
    let size = NSSize(width: imageWidth, height: 22)
    let image = NSImage(size: size)

    image.lockFocus()

    // Draw filled circle at top
    let circleRect = NSRect(
      x: (size.width - circleSize) / 2, y: 13, width: circleSize, height: circleSize)
    let circlePath = NSBezierPath(ovalIn: circleRect)
    color.setFill()
    circlePath.fill()

    // Draw text below circle
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
