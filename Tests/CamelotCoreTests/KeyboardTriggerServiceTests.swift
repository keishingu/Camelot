import CoreGraphics
@testable import Camelot
import XCTest

@MainActor
final class KeyboardTriggerServiceTests: XCTestCase {
  func testOptionTapDeliversCallbackAfterRelease() async {
    let service = KeyboardTriggerService()
    let delivered = expectation(description: "option callback delivered")
    service.onOptionTap = { delivered.fulfill() }

    service.sampleOptionState(isDown: true, additionalInput: false, timestamp: 100)
    service.sampleOptionState(isDown: false, additionalInput: false, timestamp: 200)

    await fulfillment(of: [delivered], timeout: 1)
  }

  func testOptionTapIsCancelledByAdditionalInput() async {
    let service = KeyboardTriggerService()
    var callbackCount = 0
    service.onOptionTap = { callbackCount += 1 }

    service.sampleOptionState(isDown: true, additionalInput: false, timestamp: 100)
    service.sampleOptionState(isDown: true, additionalInput: true, timestamp: 150)
    service.sampleOptionState(isDown: false, additionalInput: false, timestamp: 200)
    await Task.yield()

    XCTAssertEqual(callbackCount, 0)
  }

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

  func testEveryHintKeyConsumesDownAndUpAndDeliversExpectedCharacter() async {
    let mappings: [(CGKeyCode, Character)] = [
      (0, "A"), (1, "S"), (2, "D"), (3, "F"), (4, "H"), (5, "G"),
      (6, "Z"), (7, "X"), (8, "C"), (9, "V"), (11, "B"), (12, "Q"),
      (13, "W"), (14, "E"), (15, "R"), (16, "Y"), (17, "T"), (31, "O"),
      (32, "U"), (34, "I"), (35, "P"), (37, "L"), (38, "J"), (40, "K"),
      (45, "N"), (46, "M"),
    ]
    let service = KeyboardTriggerService()
    service.setHintModeActive(true)
    let delivered = expectation(description: "all hint callbacks delivered")
    delivered.expectedFulfillmentCount = mappings.count
    var characters = [Character]()
    service.onHintCharacter = {
      characters.append($0)
      delivered.fulfill()
    }

    for (keyCode, _) in mappings {
      XCTAssertTrue(service.handle(.keyDown, event: keyEvent(keyCode, down: true)))
      XCTAssertTrue(service.handle(.keyUp, event: keyEvent(keyCode, down: false)))
    }

    await fulfillment(of: [delivered], timeout: 1)
    XCTAssertEqual(characters, mappings.map(\.1))
  }

  func testBackspaceConsumesBothEventsAndDeliversOnce() async {
    let service = KeyboardTriggerService()
    service.setHintModeActive(true)
    let delivered = expectation(description: "backspace callback delivered")
    service.onBackspace = { delivered.fulfill() }

    XCTAssertTrue(service.handle(.keyDown, event: keyEvent(51, down: true)))
    XCTAssertTrue(service.handle(.keyUp, event: keyEvent(51, down: false)))

    await fulfillment(of: [delivered], timeout: 1)
  }

  func testUnknownAndRepeatedKeysAreConsumedWithoutCallbacks() async {
    let service = KeyboardTriggerService()
    service.setHintModeActive(true)
    var callbackCount = 0
    service.onHintCharacter = { _ in callbackCount += 1 }
    service.onBackspace = { callbackCount += 1 }
    service.onCancel = { callbackCount += 1 }

    let unknown = keyEvent(123, down: true)
    XCTAssertTrue(service.handle(.keyDown, event: unknown))
    XCTAssertTrue(service.handle(.keyUp, event: keyEvent(123, down: false)))

    let repeated = keyEvent(0, down: true)
    repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
    XCTAssertTrue(service.handle(.keyDown, event: repeated))
    await Task.yield()
    XCTAssertEqual(callbackCount, 0)
  }

  func testMouseInputCancelsModeAndRestoresKeyPassThrough() async {
    let service = KeyboardTriggerService()
    service.setHintModeActive(true)
    let cancelled = expectation(description: "mouse cancellation delivered")
    service.onCancel = { cancelled.fulfill() }
    let mouse = CGEvent(
      mouseEventSource: nil,
      mouseType: .leftMouseDown,
      mouseCursorPosition: .zero,
      mouseButton: .left
    )!

    XCTAssertFalse(service.handle(.leftMouseDown, event: mouse))
    XCTAssertFalse(service.handle(.keyDown, event: keyEvent(0, down: true)))

    await fulfillment(of: [cancelled], timeout: 1)
  }

  func testKeyUpRemainsConsumedAfterSelectionEndsMode() {
    let service = KeyboardTriggerService()
    service.setHintModeActive(true)

    XCTAssertTrue(service.handle(.keyDown, event: keyEvent(0, down: true)))
    service.setHintModeActive(false)
    XCTAssertTrue(service.handle(.keyUp, event: keyEvent(0, down: false)))
  }

  private func keyEvent(_ keyCode: CGKeyCode, down: Bool) -> CGEvent {
    CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)!
  }
}
