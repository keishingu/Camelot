import AppKit
import ApplicationServices
import Foundation

enum AccessibilityExecutionError: LocalizedError, Sendable {
  case applicationChanged
  case windowChanged
  case elementDisabled
  case actionFailed(AXError)

  var errorDescription: String? {
    switch self {
    case .applicationChanged:
      "The frontmost application changed"
    case .windowChanged:
      "The focused window changed"
    case .elementDisabled:
      "The selected element is no longer enabled"
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
    case .focus:
      error = AXUIElementSetAttributeValue(
        candidate.element,
        kAXFocusedAttribute as CFString,
        kCFBooleanTrue
      )
    }
    return error == .success ? .success(()) : .failure(.actionFailed(error))
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
