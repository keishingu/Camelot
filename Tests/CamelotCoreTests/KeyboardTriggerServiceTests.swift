import CoreGraphics
@testable import Camelot
import XCTest

@MainActor
final class KeyboardTriggerServiceTests: XCTestCase {
  func testSecureInputOptionTapDeliversCallbackAfterRelease() async {
    let service = KeyboardTriggerService(isSecureInputEnabled: { true })
    let delivered = expectation(description: "option callback delivered")
    service.onOptionTap = { delivered.fulfill() }

    sample(service, flags: [], changes: 0, timestamp: 0)
    sample(service, flags: .maskAlternate, changes: 1, timestamp: 100)
    sample(service, flags: [], changes: 2, timestamp: 200)

    await fulfillment(of: [delivered], timeout: 1)
  }

  func testSecureInputOptionTapIsCancelledByAdditionalInput() async {
    let service = KeyboardTriggerService(isSecureInputEnabled: { true })
    var callbackCount = 0
    service.onOptionTap = { callbackCount += 1 }

    sample(service, flags: [], changes: 0, timestamp: 0)
    sample(service, flags: .maskAlternate, changes: 1, timestamp: 100)
    sample(service, flags: .maskAlternate, keys: 1, changes: 1, timestamp: 150)
    sample(service, flags: [], keys: 1, changes: 2, timestamp: 200)
    await flushCallbacks()

    XCTAssertEqual(callbackCount, 0)
  }

  func testHintCallbackRunsAfterConsumptionDecisionReturns() async {
    let service = KeyboardTriggerService(isSecureInputEnabled: { false })
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
    let service = KeyboardTriggerService(isSecureInputEnabled: { false })
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
    let service = KeyboardTriggerService(isSecureInputEnabled: { false })
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
    let service = KeyboardTriggerService(isSecureInputEnabled: { false })
    service.setHintModeActive(true)
    let delivered = expectation(description: "backspace callback delivered")
    service.onBackspace = { delivered.fulfill() }

    XCTAssertTrue(service.handle(.keyDown, event: keyEvent(51, down: true)))
    XCTAssertTrue(service.handle(.keyUp, event: keyEvent(51, down: false)))

    await fulfillment(of: [delivered], timeout: 1)
  }

  func testUnknownAndRepeatedKeysAreConsumedWithoutCallbacks() async {
    let service = KeyboardTriggerService(isSecureInputEnabled: { false })
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
    let service = KeyboardTriggerService(isSecureInputEnabled: { false })
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
    let service = KeyboardTriggerService(isSecureInputEnabled: { false })
    service.setHintModeActive(true)

    XCTAssertTrue(service.handle(.keyDown, event: keyEvent(0, down: true)))
    service.setHintModeActive(false)
    XCTAssertTrue(service.handle(.keyUp, event: keyEvent(0, down: false)))
  }

  func testNormalEventTapDetectsLeftAndRightTapsBetweenPolls() async {
    let service = KeyboardTriggerService(isSecureInputEnabled: { false })
    var callbackCount = 0
    service.onOptionTap = { callbackCount += 1 }

    for keyCode: CGKeyCode in [58, 61] {
      sample(service, secure: false, flags: [], changes: 0, timestamp: 0)
      optionEvent(service, keyCode: keyCode, down: true, timestamp: 40_000_000)
      optionEvent(service, keyCode: keyCode, down: false, timestamp: 140_000_000)
      sample(service, secure: false, flags: [], changes: 2, timestamp: 250_000_000)
    }
    await flushCallbacks()

    XCTAssertEqual(callbackCount, 2)
  }

  func testNormalPollDoesNotCancelAnEventTapGesture() async {
    let service = KeyboardTriggerService(isSecureInputEnabled: { false })
    var callbackCount = 0
    service.onOptionTap = { callbackCount += 1 }

    optionEvent(service, down: true, timestamp: 40_000_000)
    sample(service, secure: false, flags: .maskAlternate, changes: 1, timestamp: 70_000_000)
    optionEvent(service, down: false, timestamp: 140_000_000)
    await flushCallbacks()

    XCTAssertEqual(callbackCount, 1)
  }

  func testNormalModeIgnoresFallbackSamples() async {
    let service = KeyboardTriggerService(isSecureInputEnabled: { false })
    var callbackCount = 0
    service.onOptionTap = { callbackCount += 1 }

    sample(service, secure: false, flags: [], changes: 0, timestamp: 0)
    sample(service, secure: false, flags: .maskAlternate, changes: 1, timestamp: 40_000_000)
    sample(service, secure: false, flags: [], changes: 2, timestamp: 140_000_000)
    await flushCallbacks()

    XCTAssertEqual(callbackCount, 0)
  }

  func testSecureInputIgnoresEventTapFlagsAndUsesPollingOnce() async {
    let service = KeyboardTriggerService(isSecureInputEnabled: { true })
    var callbackCount = 0
    service.onOptionTap = { callbackCount += 1 }

    sample(service, flags: [], changes: 0, timestamp: 0)
    optionEvent(service, down: true, timestamp: 40_000_000)
    sample(service, flags: .maskAlternate, changes: 1, timestamp: 40_000_000)
    optionEvent(service, down: false, timestamp: 140_000_000)
    await flushCallbacks()
    XCTAssertEqual(callbackCount, 0)

    sample(service, flags: [], changes: 2, timestamp: 140_000_000)
    await flushCallbacks()
    XCTAssertEqual(callbackCount, 1)
  }

  func testSecureInputRejectsModifierShortcutsLongHoldsAndAnAlreadyHeldOption() async {
    let samples: [[(CGEventFlags, UInt32, UInt64)]] = [
      [([], 0, 0), (.maskAlternate, 1, 40_000_000),
       ([.maskAlternate, .maskShift], 2, 70_000_000), ([], 4, 140_000_000)],
      [([], 0, 0), (.maskAlternate, 1, 40_000_000),
       (.maskAlternate, 3, 70_000_000), ([], 4, 140_000_000)],
      [([], 0, 0), (.maskAlternate, 1, 40_000_000), ([], 2, 400_000_000)],
      [(.maskAlternate, 1, 40_000_000), ([], 2, 140_000_000)],
    ]
    for (index, observations) in samples.enumerated() {
      let service = KeyboardTriggerService(isSecureInputEnabled: { true })
      var callbackCount = 0
      service.onOptionTap = { callbackCount += 1 }
      for (flags, changes, timestamp) in observations {
        sample(service, flags: flags, changes: changes, timestamp: timestamp)
      }
      await flushCallbacks()
      XCTAssertEqual(callbackCount, 0, "observation sequence \(index)")
    }
  }

  func testEnablingSecureInputDiscardsTheNormalGesture() async {
    var secure = false
    let service = KeyboardTriggerService(isSecureInputEnabled: { secure })
    var callbackCount = 0
    service.onOptionTap = { callbackCount += 1 }

    optionEvent(service, down: true, timestamp: 40_000_000)
    secure = true
    sample(service, flags: .maskAlternate, changes: 1, timestamp: 70_000_000)
    sample(service, flags: [], changes: 2, timestamp: 140_000_000)
    await flushCallbacks()
    XCTAssertEqual(callbackCount, 0)

    sample(service, flags: .maskAlternate, changes: 3, timestamp: 200_000_000)
    sample(service, flags: [], changes: 4, timestamp: 250_000_000)
    await flushCallbacks()
    XCTAssertEqual(callbackCount, 1)
  }

  func testDisablingSecureInputDiscardsThePolledGestureAndRestoresEvents() async {
    var secure = true
    let service = KeyboardTriggerService(isSecureInputEnabled: { secure })
    var callbackCount = 0
    service.onOptionTap = { callbackCount += 1 }

    sample(service, flags: [], changes: 0, timestamp: 0)
    sample(service, flags: .maskAlternate, changes: 1, timestamp: 40_000_000)
    secure = false
    optionEvent(service, down: false, timestamp: 140_000_000)
    await flushCallbacks()
    XCTAssertEqual(callbackCount, 0)

    optionEvent(service, down: true, timestamp: 200_000_000)
    optionEvent(service, down: false, timestamp: 250_000_000)
    sample(service, secure: false, flags: [], changes: 4, timestamp: 260_000_000)
    await flushCallbacks()
    XCTAssertEqual(callbackCount, 1)
  }

  func testSecureInputOptionHeldDuringHintModeDoesNotTriggerOnRelease() async {
    let service = KeyboardTriggerService(isSecureInputEnabled: { true })
    var callbackCount = 0
    service.onOptionTap = { callbackCount += 1 }

    sample(service, flags: [], changes: 0, timestamp: 0)
    service.setHintModeActive(true)
    sample(service, flags: .maskAlternate, changes: 1, timestamp: 40_000_000)
    service.setHintModeActive(false)
    sample(service, flags: [], changes: 2, timestamp: 140_000_000)
    await flushCallbacks()
    XCTAssertEqual(callbackCount, 0)

    sample(service, flags: .maskAlternate, changes: 3, timestamp: 200_000_000)
    sample(service, flags: [], changes: 4, timestamp: 250_000_000)
    await flushCallbacks()
    XCTAssertEqual(callbackCount, 1)
  }

  func testStopDiscardsTheSecureInputGesture() async {
    let service = KeyboardTriggerService(isSecureInputEnabled: { true })
    var callbackCount = 0
    service.onOptionTap = { callbackCount += 1 }

    sample(service, flags: [], changes: 0, timestamp: 0)
    sample(service, flags: .maskAlternate, changes: 1, timestamp: 40_000_000)
    service.stop()
    sample(service, flags: [], changes: 2, timestamp: 140_000_000)
    await flushCallbacks()
    XCTAssertEqual(callbackCount, 0)

    sample(service, flags: .maskAlternate, changes: 3, timestamp: 200_000_000)
    sample(service, flags: [], changes: 4, timestamp: 250_000_000)
    await flushCallbacks()
    XCTAssertEqual(callbackCount, 1)
  }

  private func sample(
    _ service: KeyboardTriggerService,
    secure: Bool = true,
    flags: CGEventFlags,
    keys: UInt32 = 0,
    changes: UInt32,
    timestamp: UInt64
  ) {
    service.sampleOptionState(
      secureInputEnabled: secure,
      flags: flags,
      keyDownCount: keys,
      flagsChangedCount: changes,
      timestamp: timestamp
    )
  }

  private func optionEvent(
    _ service: KeyboardTriggerService,
    keyCode: CGKeyCode = 58,
    down: Bool,
    timestamp: UInt64
  ) {
    let event = keyEvent(keyCode, down: down)
    event.type = .flagsChanged
    event.flags = down ? .maskAlternate : []
    event.timestamp = timestamp
    XCTAssertFalse(service.handle(.flagsChanged, event: event))
  }

  private func flushCallbacks() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }

  private func keyEvent(_ keyCode: CGKeyCode, down: Bool) -> CGEvent {
    CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)!
  }
}
