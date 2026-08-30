import AppKit
import ApplicationServices
@testable import Camelot
import XCTest

@MainActor
final class CamelotAppModelTests: XCTestCase {
  func testOptionTapStartsScanWhenPermissionsAndEventTapAreReady() {
    _ = NSApplication.shared
    let scanner = AccessibilityScannerSpy()
    let keyboard = KeyboardTriggerStub()
    let model = CamelotAppModel(
      scanner: scanner,
      keyboardTrigger: keyboard,
      permissionSnapshot: {
        PermissionSnapshot(accessibility: true, inputMonitoring: true)
      }
    )

    keyboard.onOptionTap?()

    XCTAssertEqual(scanner.scanCount, 1)
    XCTAssertEqual(model.status, "Scanning the focused window…")
  }

  func testHintCharacterEndsSessionAndAttemptsExecution() {
    let scanner = AccessibilityScannerSpy()
    let keyboard = KeyboardTriggerStub()
    let model = makeModel(scanner: scanner, keyboard: keyboard)

    keyboard.onOptionTap?()
    scanner.complete(with: oneCandidateScan())
    XCTAssertTrue(model.isHintModeActive)

    keyboard.onHintCharacter?("A")

    XCTAssertFalse(model.isHintModeActive)
    XCTAssertEqual(keyboard.hintModeStates, [false, true, false])
    XCTAssertTrue(model.status.contains("action=press"))
  }

  func testEscapeEndsActiveHintSession() {
    let scanner = AccessibilityScannerSpy()
    let keyboard = KeyboardTriggerStub()
    let model = makeModel(scanner: scanner, keyboard: keyboard)

    keyboard.onOptionTap?()
    scanner.complete(with: oneCandidateScan())
    XCTAssertTrue(model.isHintModeActive)

    keyboard.onCancel?()

    XCTAssertFalse(model.isHintModeActive)
    XCTAssertEqual(keyboard.hintModeStates, [false, true, false])
    XCTAssertEqual(model.status, "Hint Mode cancelled")
  }

  private func makeModel(
    scanner: AccessibilityScannerSpy,
    keyboard: KeyboardTriggerStub
  ) -> CamelotAppModel {
    CamelotAppModel(
      scanner: scanner,
      keyboardTrigger: keyboard,
      permissionSnapshot: {
        PermissionSnapshot(accessibility: true, inputMonitoring: true)
      }
    )
  }

  private func oneCandidateScan() -> AccessibilityScanResult {
    let element = AXUIElementCreateSystemWide()
    return AccessibilityScanResult(
      applicationName: "Test App",
      visitedNodeCount: 1,
      candidates: [
        AccessibilityCandidate(
          id: 0,
          pid: -1,
          role: "AXButton",
          subrole: nil,
          frame: CGRect(x: 100, y: 100, width: 80, height: 30),
          activationPoint: CGPoint(x: 140, y: 115),
          action: .press,
          element: element,
          window: element
        )
      ],
      duration: 0.01,
      reachedSafetyLimit: false
    )
  }
}

private final class AccessibilityScannerSpy: AccessibilityScanning {
  private(set) var scanCount = 0
  private var completion: ((Result<AccessibilityScanResult, ScanError>) -> Void)?

  func scanFrontmostApplication(
    completion: @escaping (Result<AccessibilityScanResult, ScanError>) -> Void
  ) {
    scanCount += 1
    self.completion = completion
  }

  func complete(with result: AccessibilityScanResult) {
    completion?(.success(result))
  }
}

private final class KeyboardTriggerStub: KeyboardTriggering {
  var onOptionTap: (() -> Void)?
  var onHintCharacter: ((Character) -> Void)?
  var onBackspace: (() -> Void)?
  var onCancel: (() -> Void)?
  var isRunning = true
  private(set) var hintModeStates = [Bool]()

  func start() -> Bool { true }
  func stop() {}
  func setHintModeActive(_ active: Bool) { hintModeStates.append(active) }
}
