import CoreGraphics
@testable import Camelot
import XCTest

@MainActor
final class KeyboardTriggerServiceTests: XCTestCase {
  func testHintCallbackRunsAfterConsumptionDecisionReturns() async {
    let service = KeyboardTriggerService()
    service.setHintModeActive(true)
    let delivered = expectation(description: "hint callback delivered")
    var handlerReturned = false
    service.onHintCharacter = { character in
      XCTAssertEqual(character, "A")
      XCTAssertTrue(handlerReturned)
      delivered.fulfill()
    }

    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    XCTAssertTrue(service.handle(.keyDown, event: event))
    handlerReturned = true

    await fulfillment(of: [delivered], timeout: 1)
  }

  func testEscapeImmediatelyEndsModeAndConsumesKeyUp() async {
    let service = KeyboardTriggerService()
    service.setHintModeActive(true)
    let cancelled = expectation(description: "cancel callback delivered")
    service.onCancel = { cancelled.fulfill() }

    let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
    let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)!
    XCTAssertTrue(service.handle(.keyDown, event: down))
    XCTAssertTrue(service.handle(.keyUp, event: up))

    await fulfillment(of: [cancelled], timeout: 1)
  }
}
