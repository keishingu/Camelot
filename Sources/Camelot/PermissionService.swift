import ApplicationServices
import Carbon
import CoreGraphics

struct PermissionSnapshot: Equatable {
  let accessibility: Bool
  let inputMonitoring: Bool
}

enum PermissionService {
  static var isSecureInputEnabled: Bool {
    IsSecureEventInputEnabled()
  }

  static var current: PermissionSnapshot {
    PermissionSnapshot(
      accessibility: AXIsProcessTrusted(),
      inputMonitoring: CGPreflightListenEventAccess()
    )
  }

  @discardableResult
  static func requestAccessibility() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    return AXIsProcessTrustedWithOptions(options as CFDictionary)
  }

  @discardableResult
  static func requestInputMonitoring() -> Bool {
    CGRequestListenEventAccess()
  }
}
