import AppKit
import ApplicationServices
import CamelotCore
import Foundation

enum CandidateAction: String, Sendable {
  case press
  case showMenu
  case pick
  case focus
  case click
}

struct AccessibilityCandidate: Identifiable, @unchecked Sendable {
  var id: Int
  let pid: pid_t
  let role: String
  let subrole: String?
  let frame: CGRect
  let activationPoint: CGPoint
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

protocol AccessibilityScanning {
  func scanFrontmostApplication(
    completion: @escaping (Result<AccessibilityScanResult, ScanError>) -> Void
  )
}

final class AccessibilityScanner: AccessibilityScanning {
  private struct Request {
    let pid: pid_t
    let applicationName: String
    let appKitScreenFrames: [CGRect]
    let primaryScreenMaxY: CGFloat
  }

  private static let maximumNodes = 5_000
  private static let maximumDepth = 50
  private static let maximumDuration: TimeInterval = 0.75
  static let childAttributePriority = [
    "AXChildrenInNavigationOrder",
    kAXVisibleChildrenAttribute,
    kAXChildrenAttribute,
  ]
  private static let focusableRoles: Set<String> = [
    "AXTextField", "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor",
  ]
  private static let semanticActionRoles: Set<String> = [
    "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXMenuItem",
    "AXPopUpButton", "AXMenuButton", "AXTab", "AXDisclosureTriangle",
  ]
  private static let menuPresentationRoles: Set<String> = [
    "AXPopUpButton", "AXMenuButton",
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
    AXUIElementSetAttributeValue(
      application,
      "AXManualAccessibility" as CFString,
      kCFBooleanTrue
    )
    guard let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: application) else {
      return .failure(.noFocusedWindow)
    }

    var stack: [(AXUIElement, Int)] = [(focusedWindow, 0)]
    var visitedHashes = Set<CFHashCode>()
    var candidates = [AccessibilityCandidate]()
    var candidateIndexByGeometry = [String: Int]()
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
          String(Int(candidate.frame.origin.x.rounded())),
          String(Int(candidate.frame.origin.y.rounded())),
          String(Int(candidate.frame.width.rounded())),
          String(Int(candidate.frame.height.rounded())),
        ].joined(separator: ":")
        if let existingIndex = candidateIndexByGeometry[signature] {
          let existing = candidates[existingIndex]
          if candidatePriority(candidate) <= candidatePriority(existing) {
            var replacement = candidate
            replacement.id = existing.id
            candidates[existingIndex] = replacement
          }
        } else {
          candidateIndexByGeometry[signature] = candidates.count
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

    let actions = Set(actionNames(of: element))
    guard let action = preferredAction(
      role: role,
      actions: actions,
      canFocus: Self.focusableRoles.contains(role) && isFocusedAttributeSettable(on: element),
      frame: axFrame
    ) else {
      return nil
    }

    return AccessibilityCandidate(
      id: id,
      pid: request.pid,
      role: role,
      subrole: attribute(kAXSubroleAttribute, from: element) as? String,
      frame: appKitFrame,
      activationPoint: CGPoint(x: axFrame.midX, y: axFrame.midY),
      action: action,
      element: element,
      window: window
    )
  }

  private func childElements(of element: AXUIElement) -> [AXUIElement] {
    for attributeName in Self.childAttributePriority {
      if let children = attribute(attributeName, from: element) as? [AXUIElement],
        !children.isEmpty
      {
        return children
      }
    }
    return []
  }

  func candidatePriority(_ candidate: AccessibilityCandidate) -> Int {
    if candidate.action == .focus { return 0 }
    if Self.semanticActionRoles.contains(candidate.role) { return 1 }
    return 2
  }

  func preferredAction(
    role: String,
    actions: Set<String>,
    canFocus: Bool,
    frame: CGRect
  ) -> CandidateAction? {
    if Self.focusableRoles.contains(role), canFocus { return .focus }
    if role == "AXButton", frame.width >= frame.height * 5 { return .click }
    if actions.contains(kAXPressAction as String) { return .press }
    if Self.menuPresentationRoles.contains(role), actions.contains(kAXShowMenuAction as String) {
      return .showMenu
    }
    if actions.contains(kAXPickAction as String) { return .pick }
    return Self.semanticActionRoles.contains(role) ? .click : nil
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
