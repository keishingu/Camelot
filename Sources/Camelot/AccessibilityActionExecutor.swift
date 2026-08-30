import AppKit
import ApplicationServices
import Foundation

enum AccessibilityExecutionError: LocalizedError, Sendable {
  case applicationChanged
  case windowChanged
  case elementDisabled
  case clickEventCreationFailed
  case actionFailed(AXError)

  var errorDescription: String? {
    switch self {
    case .applicationChanged:
      "The frontmost application changed"
    case .windowChanged:
      "The focused window changed"
    case .elementDisabled:
      "The selected element is no longer enabled"
    case .clickEventCreationFailed:
      "The fallback click could not be created"
    case .actionFailed(let error):
      "Accessibility action failed (\(error.rawValue))"
    }
  }
}

final class AccessibilityActionExecutor {
  private let queue = DispatchQueue(label: "com.camelot.accessibility-execution")

  func execute(
    _ candidate: AccessibilityCandidate,
    completion: @escaping (Result<Void, AccessibilityExecutionError>) -> Void
  ) {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == candidate.pid else {
      completion(.failure(.applicationChanged))
      return
    }

    queue.async {
      let result = self.executeOnQueue(candidate)
      DispatchQueue.main.async { completion(result) }
    }
  }

  private func executeOnQueue(
    _ candidate: AccessibilityCandidate
  ) -> Result<Void, AccessibilityExecutionError> {
    let application = AXUIElementCreateApplication(candidate.pid)
    guard
      let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: application),
      CFEqual(focusedWindow, candidate.window)
    else {
      return .failure(.windowChanged)
    }

    let enabled = attribute(kAXEnabledAttribute, from: candidate.element) as? Bool ?? true
    guard enabled else { return .failure(.elementDisabled) }

    let error: AXError
    switch candidate.action {
    case .press:
      error = AXUIElementPerformAction(candidate.element, kAXPressAction as CFString)
    case .showMenu:
      error = AXUIElementPerformAction(candidate.element, kAXShowMenuAction as CFString)
    case .pick:
      error = AXUIElementPerformAction(candidate.element, kAXPickAction as CFString)
    case .focus:
      error = AXUIElementSetAttributeValue(
        candidate.element,
        kAXFocusedAttribute as CFString,
        kCFBooleanTrue
      )
    case .click:
      return coordinateClick(candidate)
    }
    if error == .actionUnsupported { return coordinateClick(candidate) }
    return error == .success ? .success(()) : .failure(.actionFailed(error))
  }

  private func coordinateClick(
    _ candidate: AccessibilityCandidate
  ) -> Result<Void, AccessibilityExecutionError> {
    let point = currentActivationPoint(for: candidate.element) ?? candidate.activationPoint
    guard
      let down = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseDown,
        mouseCursorPosition: point,
        mouseButton: .left
      ),
      let up = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseUp,
        mouseCursorPosition: point,
        mouseButton: .left
      )
    else {
      return .failure(.clickEventCreationFailed)
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return .success(())
  }

  private func currentActivationPoint(for element: AXUIElement) -> CGPoint? {
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
    return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
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
