import CamelotCore
import CoreGraphics
import Foundation

final class KeyboardTriggerService {
  private static let leftOption: CGKeyCode = 58
  private static let rightOption: CGKeyCode = 61
  private static let escape: CGKeyCode = 53
  private static let delete: CGKeyCode = 51
  private static let hintCharacters: [CGKeyCode: Character] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
    8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
    16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
    38: "J", 40: "K", 45: "N", 46: "M",
  ]

  var onOptionTap: (() -> Void)?
  var onHintCharacter: ((Character) -> Void)?
  var onBackspace: (() -> Void)?
  var onCancel: (() -> Void)?

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var tapDetector = OptionTapDetector()
  private var hintModeActive = false
  private var suppressedKeyCodes = Set<CGKeyCode>()

  var isRunning: Bool { eventTap != nil }

  @discardableResult
  func start() -> Bool {
    stop()

    let eventMask = [
      CGEventType.flagsChanged,
      .keyDown,
      .keyUp,
      .leftMouseDown,
      .rightMouseDown,
      .otherMouseDown,
      .scrollWheel,
    ].reduce(CGEventMask(0)) { mask, type in
      mask | (CGEventMask(1) << type.rawValue)
    }

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: { _, eventType, event, userInfo in
          guard let userInfo else { return Unmanaged.passUnretained(event) }
          let service = Unmanaged<KeyboardTriggerService>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
          if service.handle(eventType, event: event) {
            return nil
          }
          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      return false
    }

    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
      CFMachPortInvalidate(eventTap)
      return false
    }

    self.eventTap = eventTap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    return true
  }

  func stop() {
    hintModeActive = false
    suppressedKeyCodes.removeAll()
    tapDetector.cancel()
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFRunLoopSourceInvalidate(runLoopSource)
    }
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    runLoopSource = nil
    eventTap = nil
  }

  func setHintModeActive(_ active: Bool) {
    hintModeActive = active
    if active { suppressedKeyCodes.removeAll() }
    tapDetector.cancel()
  }

  private func handle(_ type: CGEventType, event: CGEvent) -> Bool {
    if type == .keyUp {
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
      if suppressedKeyCodes.remove(keyCode) != nil { return true }
    }

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      let wasActive = hintModeActive
      setHintModeActive(false)
      if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
      if wasActive { onCancel?() }
      return false
    }

    if hintModeActive {
      return handleHintMode(type, event: event)
    }

    guard type == .flagsChanged else {
      tapDetector.cancel()
      return false
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    guard keyCode == Self.leftOption || keyCode == Self.rightOption else {
      tapDetector.cancel()
      return false
    }

    let isDown = event.flags.contains(.maskAlternate)
    let optionKey: OptionTapDetector.Key = keyCode == Self.leftOption ? .left : .right
    if tapDetector.optionChanged(optionKey, isDown: isDown, timestamp: event.timestamp) {
      onOptionTap?()
    }
    return false
  }

  private func handleHintMode(_ type: CGEventType, event: CGEvent) -> Bool {
    if [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(type) {
      setHintModeActive(false)
      onCancel?()
      return false
    }

    guard type == .keyDown || type == .keyUp else { return false }
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    if type == .keyUp {
      return suppressedKeyCodes.remove(keyCode) != nil
    }

    suppressedKeyCodes.insert(keyCode)
    if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
    if keyCode == Self.escape {
      setHintModeActive(false)
      onCancel?()
    } else if keyCode == Self.delete {
      onBackspace?()
    } else if let character = Self.hintCharacters[keyCode] {
      onHintCharacter?(character)
    }
    return true
  }

  deinit {
    stop()
  }
}
