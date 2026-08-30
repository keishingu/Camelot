import AppKit
import SwiftUI

struct HintOverlayItem: Identifiable {
  let id: Int
  let code: String
  let frame: CGRect
  let typedCount: Int
}

@MainActor
final class OverlayWindowController {
  private var panels: [CGDirectDisplayID: HintPanel] = [:]

  func show(_ items: [HintOverlayItem]) {
    let screens = NSScreen.screens
    let activeDisplayIDs = Set(screens.compactMap(displayID))

    for id in panels.keys.filter({ !activeDisplayIDs.contains($0) }) {
      panels[id]?.orderOut(nil)
      panels[id] = nil
    }

    var keyPanel: HintPanel?
    for screen in screens {
      guard let id = displayID(for: screen) else { continue }
      let panel = panels[id] ?? makePanel(for: screen)
      panels[id] = panel
      panel.setFrame(screen.frame, display: true)

      let screenItems = items.filter { item in
        screen.frame.contains(CGPoint(x: item.frame.midX, y: item.frame.midY))
      }
      panel.contentView = NSHostingView(
        rootView: HintOverlayView(items: screenItems, screenFrame: screen.frame)
      )
      panel.orderFrontRegardless()
      if keyPanel == nil, !screenItems.isEmpty { keyPanel = panel }
    }
    keyPanel?.makeKey()
  }

  func hide() {
    for panel in panels.values {
      panel.orderOut(nil)
    }
  }

  private func makePanel(for screen: NSScreen) -> HintPanel {
    let panel = HintPanel(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false,
      screen: screen
    )
    panel.level = .statusBar
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .transient,
      .ignoresCycle,
    ]
    return panel
  }

  private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
      .map { CGDirectDisplayID($0.uint32Value) }
  }
}

private final class HintPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

private struct HintOverlayView: View {
  let items: [HintOverlayItem]
  let screenFrame: CGRect

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color.clear
      ForEach(items) { item in
        HintBadge(code: item.code, typedCount: item.typedCount)
          .position(position(for: item.frame))
      }
    }
    .frame(width: screenFrame.width, height: screenFrame.height)
    .accessibilityHidden(true)
  }

  private func position(for frame: CGRect) -> CGPoint {
    let x = min(max(frame.minX - screenFrame.minX + 12, 18), screenFrame.width - 18)
    let y = min(max(screenFrame.maxY - frame.maxY + 10, 12), screenFrame.height - 12)
    return CGPoint(x: x, y: y)
  }
}

private struct HintBadge: View {
  let code: String
  let typedCount: Int

  var body: some View {
    label
      .font(.system(size: 12, weight: .bold, design: .rounded))
      .monospaced()
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
  }

  private var label: some View {
    HStack(spacing: 0) {
      ForEach(Array(code.enumerated()), id: \.offset) { part in
        Text(String(part.element))
          .foregroundStyle(part.offset < typedCount ? .yellow : .primary)
      }
    }
  }
}
