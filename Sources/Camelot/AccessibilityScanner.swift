import AppKit
import ApplicationServices
import CamelotCore
import Foundation

enum CandidateAction: String, Sendable {
  case press
  case focus
}

struct AccessibilityCandidate: Identifiable, @unchecked Sendable {
  let id: Int
  let pid: pid_t
  let role: String
  let subrole: String?
  let frame: CGRect
  let action: CandidateAction
  let element: AXUIElement
  let window: AXUIElement
}

struct AccessibilityScanResult: Sendable {
  let applicationName: String
  let visitedNodeCount: Int
  let candidates: [AccessibilityCandidate]
  let duration: TimeInterval
  let reachedSafetyLimit: Bool
}

final class AccessibilityScanner {
  private struct Request {
    let pid: pid_t
    let applicationName: String
    let appKitScreenFrames: [CGRect]
    let primaryScreenMaxY: CGFloat
  }

  private static let maximumNodes = 5_000
  private static let maximumDepth = 50
  private static let maximumDuration: TimeInterval = 0.75
  private static let focusableRoles: Set<String> = [
    "AXTextField", "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor",
  ]

  private let queue = DispatchQueue(label: "com.camelot.accessibility-scan")

  func scanFrontmostApplication(
    completion: @escaping (Result<AccessibilityScanResult, ScanError>) -> Void
  ) {
    guard let application = NSWorkspace.shared.frontmostApplication else {
      completion(.failure(.noFrontmostApplication))
      return
    }

    let screens = NSScreen.screens
    let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
    let request = Request(
      pid: application.processIdentifier,
      applicationName: application.localizedName ?? application.bundleIdentifier ?? "Unknown",
      appKitScreenFrames: screens.map(\.frame),
      primaryScreenMaxY: primary?.frame.maxY ?? 0
    )

    queue.async { [weak self] in
      guard let self else { return }
      let result = scan(request)
      DispatchQueue.main.async { completion(result) }
    }
  }

  private func scan(_ request: Request) -> Result<AccessibilityScanResult, ScanError> {
    let startedAt = CFAbsoluteTimeGetCurrent()
    let application = AXUIElementCreateApplication(request.pid)
    guard let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: application) else {
      return .failure(.noFocusedWindow)
    }

    var stack: [(AXUIElement, Int)] = [(focusedWindow, 0)]
    var visitedHashes = Set<CFHashCode>()
    var candidates = [AccessibilityCandidate]()
    var signatures = Set<String>()
    var visitedCount = 0
    var reachedSafetyLimit = false

    while let (element, depth) = stack.popLast() {
      let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
      guard visitedCount < Self.maximumNodes, elapsed < Self.maximumDuration else {
        reachedSafetyLimit = true
        break
      }

      let hash = CFHash(element)
      guard visitedHashes.insert(hash).inserted else { continue }
      visitedCount += 1

      if let candidate = candidate(
        from: element,
        window: focusedWindow,
        id: candidates.count,
        request: request
      ) {
        let signature = [
          candidate.role,
          candidate.action.rawValue,
          String(Int(candidate.frame.origin.x.rounded())),
          String(Int(candidate.frame.origin.y.rounded())),
          String(Int(candidate.frame.width.rounded())),
          String(Int(candidate.frame.height.rounded())),
        ].joined(separator: ":")
        if signatures.insert(signature).inserted {
          candidates.append(candidate)
        }
      }

      guard depth < Self.maximumDepth else {
        reachedSafetyLimit = true
        continue
      }
      let children = childElements(of: element)
      stack.append(contentsOf: children.reversed().map { ($0, depth + 1) })
    }

    return .success(
      AccessibilityScanResult(
        applicationName: request.applicationName,
        visitedNodeCount: visitedCount,
        candidates: candidates,
        duration: CFAbsoluteTimeGetCurrent() - startedAt,
        reachedSafetyLimit: reachedSafetyLimit
      )
    )
  }

  private func candidate(
    from element: AXUIElement,
    window: AXUIElement,
    id: Int,
    request: Request
  ) -> AccessibilityCandidate? {
    let enabled = attribute(kAXEnabledAttribute, from: element) as? Bool ?? true
    guard enabled,
      let role = attribute(kAXRoleAttribute, from: element) as? String,
      let axFrame = frame(of: element),
      axFrame.width > 0,
      axFrame.height > 0
    else {
      return nil
    }

    let appKitFrame = ScreenCoordinateConverter(
      primaryScreenMaxY: request.primaryScreenMaxY
    ).appKitFrame(fromAccessibilityFrame: axFrame)
    guard request.appKitScreenFrames.contains(where: { $0.intersects(appKitFrame) }) else {
      return nil
    }

    let action: CandidateAction
    if Self.focusableRoles.contains(role), isFocusedAttributeSettable(on: element) {
      action = .focus
    } else if actionNames(of: element).contains(kAXPressAction as String) {
      action = .press
    } else {
      return nil
    }

    return AccessibilityCandidate(
      id: id,
      pid: request.pid,
      role: role,
      subrole: attribute(kAXSubroleAttribute, from: element) as? String,
      frame: appKitFrame,
      action: action,
      element: element,
      window: window
    )
  }

  private func childElements(of element: AXUIElement) -> [AXUIElement] {
    if let visible = attribute(kAXVisibleChildrenAttribute, from: element) as? [AXUIElement] {
      return visible
    }
    return attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] ?? []
  }

  private func frame(of element: AXUIElement) -> CGRect? {
    guard
      let rawPosition = attribute(kAXPositionAttribute, from: element),
      let rawSize = attribute(kAXSizeAttribute, from: element),
      CFGetTypeID(rawPosition) == AXValueGetTypeID(),
      CFGetTypeID(rawSize) == AXValueGetTypeID()
    else {
      return nil
    }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard
      AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
      AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
    else {
      return nil
    }
    return CGRect(origin: position, size: size)
  }

  private func actionNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
  }

  private func isFocusedAttributeSettable(on element: AXUIElement) -> Bool {
    var settable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(
      element,
      kAXFocusedAttribute as CFString,
      &settable
    ) == .success && settable.boolValue
  }

  private func elementAttribute(
    _ name: String,
    from element: AXUIElement
  ) -> AXUIElement? {
    guard let value = attribute(name, from: element),
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
      return nil
    }
    return (value as! AXUIElement)
  }

  private func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value
  }
}

enum ScanError: LocalizedError, Sendable {
  case noFrontmostApplication
  case noFocusedWindow

  var errorDescription: String? {
    switch self {
    case .noFrontmostApplication:
      "No frontmost application"
    case .noFocusedWindow:
      "The frontmost application has no accessible focused window"
    }
  }
}
