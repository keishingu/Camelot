import AppKit
import CamelotCore
import CoreGraphics
import Foundation

protocol KeyboardTriggering: AnyObject {
  var onOptionTap: (() -> Void)? { get set }
  var onHintCharacter: ((Character) -> Void)? { get set }
  var onBackspace: (() -> Void)? { get set }
  var onCancel: (() -> Void)? { get set }
  var isRunning: Bool { get }

  @discardableResult
  func start() -> Bool
  func stop()
  func setHintModeActive(_ active: Bool)
}

final class KeyboardTriggerService: KeyboardTriggering {
  private final class TapRuntime {
    let tap: CFMachPort
    let source: CFRunLoopSource

    private let stateLock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private let stopped = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?
    private var stopping = false
    private var finished = false

    init(tap: CFMachPort, source: CFRunLoopSource) {
      self.tap = tap
      self.source = source
    }

    func start() -> Bool {
      let thread = Thread { [self] in run() }
      thread.name = "Camelot keyboard event tap"
      thread.qualityOfService = .userInteractive
      thread.start()

      guard ready.wait(timeout: .now() + 1) == .success else { return false }
      return CGEvent.tapIsEnabled(tap: tap)
    }

    func stop() {
      stateLock.lock()
      guard !finished else {
        stateLock.unlock()
        return
      }
      stopping = true
      let runLoop = runLoop
      stateLock.unlock()

      if let runLoop {
        CFRunLoopStop(runLoop)
        CFRunLoopWakeUp(runLoop)
      }
      guard stopped.wait(timeout: .now() + 1) != .success else { return }
      CGEvent.tapEnable(tap: tap, enable: false)
      CFRunLoopSourceInvalidate(source)
      CFMachPortInvalidate(tap)
    }

    private func run() {
      let runLoop = CFRunLoopGetCurrent()
      var sourceWasAdded = false
      defer {
        CGEvent.tapEnable(tap: tap, enable: false)
        if sourceWasAdded {
          CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        CFRunLoopSourceInvalidate(source)
        CFMachPortInvalidate(tap)
        stateLock.lock()
        self.runLoop = nil
        finished = true
        stateLock.unlock()
        stopped.signal()
      }

      stateLock.lock()
      self.runLoop = runLoop
      let shouldStop = stopping
      stateLock.unlock()

      guard !shouldStop else {
        ready.signal()
        return
      }

      CFRunLoopAddSource(runLoop, source, .commonModes)
      sourceWasAdded = true
      CGEvent.tapEnable(tap: tap, enable: true)
      ready.signal()
      CFRunLoopRun()
    }
  }

  private enum Notification {
    case optionTap
    case hintCharacter(Character)
    case backspace
    case cancel
  }

  private struct EventDecision {
    let consume: Bool
    var notification: Notification?
    var reenableTap = false
  }

  private static let escape: CGKeyCode = 53
  private static let delete: CGKeyCode = 51
  private static let shortcutModifierFlags: CGEventFlags = [
    .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn,
  ]
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

  private let lifecycleLock = NSLock()
  private let runtimeLock = NSLock()
  private let inputStateLock = NSLock()
  private var runtime: TapRuntime?
  private var localMonitor: Any?
  private var optionPollTimer: Timer?
  private var optionWasPressed = false
  private var keyDownCount: UInt32 = 0
  private var flagsChangedCount: UInt32 = 0
  private var tapDetector = OptionTapDetector()
  private var hintModeActive = false
  private var suppressedKeyCodes = Set<CGKeyCode>()

  var isRunning: Bool {
    runtimeLock.lock()
    let runtime = runtime
    runtimeLock.unlock()
    return runtime.map { CGEvent.tapIsEnabled(tap: $0.tap) } ?? false
  }

  @discardableResult
  func start() -> Bool {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    stopRuntime()
    removeLocalMonitor()
    stopOptionPolling()
    resetInputState()

    let eventMask = [
      CGEventType.keyDown,
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

    let runtime = TapRuntime(tap: eventTap, source: source)
    runtimeLock.lock()
    self.runtime = runtime
    runtimeLock.unlock()
    guard runtime.start() else {
      runtimeLock.lock()
      if self.runtime === runtime { self.runtime = nil }
      runtimeLock.unlock()
      runtime.stop()
      return false
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) {
      [weak self] event in
      guard let self, let cgEvent = event.cgEvent else { return event }
      let type: CGEventType = event.type == .keyDown ? .keyDown : .keyUp
      return handle(type, event: cgEvent) ? nil : event
    }
    startOptionPolling()
    return true
  }

  func stop() {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    stopRuntime()
    removeLocalMonitor()
    stopOptionPolling()
    resetInputState()
  }

  func setHintModeActive(_ active: Bool) {
    inputStateLock.lock()
    defer { inputStateLock.unlock() }
    setHintModeActiveLocked(active)
  }

  private func setHintModeActiveLocked(_ active: Bool) {
    hintModeActive = active
    if active { suppressedKeyCodes.removeAll() }
    tapDetector.cancel()
  }

  func handle(_ type: CGEventType, event: CGEvent) -> Bool {
    inputStateLock.lock()
    let decision = decide(type, event: event)
    inputStateLock.unlock()

    if decision.reenableTap {
      runtimeLock.lock()
      let tap = runtime?.tap
      runtimeLock.unlock()
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
    deliver(decision.notification)
    return decision.consume
  }

  private func decide(_ type: CGEventType, event: CGEvent) -> EventDecision {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      let wasActive = hintModeActive
      setHintModeActiveLocked(false)
      return EventDecision(
        consume: false,
        notification: wasActive ? .cancel : nil,
        reenableTap: true
      )
    }

    if type == .keyUp {
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
      if suppressedKeyCodes.remove(keyCode) != nil {
        return EventDecision(consume: true)
      }
    }

    if hintModeActive {
      return decideHintMode(type, event: event)
    }

    tapDetector.cancel()
    return EventDecision(consume: false)
  }

  func sampleOptionState(isDown: Bool, additionalInput: Bool, timestamp: UInt64) {
    inputStateLock.lock()
    var notification: Notification?
    if !hintModeActive, isDown != optionWasPressed {
      optionWasPressed = isDown
      if tapDetector.optionChanged(.left, isDown: isDown, timestamp: timestamp) {
        notification = .optionTap
      }
    }
    if additionalInput {
      tapDetector.cancel()
      notification = nil
    }
    inputStateLock.unlock()
    deliver(notification)
  }

  private func decideHintMode(_ type: CGEventType, event: CGEvent) -> EventDecision {
    if [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(type) {
      setHintModeActiveLocked(false)
      return EventDecision(consume: false, notification: .cancel)
    }

    guard type == .keyDown || type == .keyUp else {
      return EventDecision(consume: false)
    }
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    if type == .keyUp {
      return EventDecision(consume: suppressedKeyCodes.remove(keyCode) != nil)
    }

    suppressedKeyCodes.insert(keyCode)
    if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
      return EventDecision(consume: true)
    }
    if keyCode == Self.escape {
      setHintModeActiveLocked(false)
      return EventDecision(consume: true, notification: .cancel)
    } else if keyCode == Self.delete {
      return EventDecision(consume: true, notification: .backspace)
    } else if let character = Self.hintCharacters[keyCode] {
      return EventDecision(consume: true, notification: .hintCharacter(character))
    }
    return EventDecision(consume: true)
  }

  private func deliver(_ notification: Notification?) {
    guard let notification else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      switch notification {
      case .optionTap:
        onOptionTap?()
      case .hintCharacter(let character):
        onHintCharacter?(character)
      case .backspace:
        onBackspace?()
      case .cancel:
        onCancel?()
      }
    }
  }

  private func stopRuntime() {
    runtimeLock.lock()
    let runtime = runtime
    self.runtime = nil
    runtimeLock.unlock()
    runtime?.stop()
  }

  private func removeLocalMonitor() {
    guard let localMonitor else { return }
    NSEvent.removeMonitor(localMonitor)
    self.localMonitor = nil
  }

  private func startOptionPolling() {
    keyDownCount = CGEventSource.counterForEventType(
      .combinedSessionState,
      eventType: .keyDown
    )
    flagsChangedCount = CGEventSource.counterForEventType(
      .combinedSessionState,
      eventType: .flagsChanged
    )
    optionWasPressed = CGEventSource.flagsState(.combinedSessionState)
      .contains(.maskAlternate)

    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      self?.pollOptionState()
    }
    timer.tolerance = 0.005
    optionPollTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func stopOptionPolling() {
    optionPollTimer?.invalidate()
    optionPollTimer = nil
  }

  private func pollOptionState() {
    let flags = CGEventSource.flagsState(.combinedSessionState)
      .intersection(Self.shortcutModifierFlags)
    let optionIsPressed = flags.contains(.maskAlternate)
    let nextKeyDownCount = CGEventSource.counterForEventType(
      .combinedSessionState,
      eventType: .keyDown
    )
    let nextFlagsChangedCount = CGEventSource.counterForEventType(
      .combinedSessionState,
      eventType: .flagsChanged
    )
    let primaryModifierChanges = optionIsPressed == optionWasPressed ? 0 : 1
    let additionalInput = nextKeyDownCount != keyDownCount
      || flags != (optionIsPressed ? .maskAlternate : [])
      || nextFlagsChangedCount &- flagsChangedCount > primaryModifierChanges
    keyDownCount = nextKeyDownCount
    flagsChangedCount = nextFlagsChangedCount

    sampleOptionState(
      isDown: optionIsPressed,
      additionalInput: additionalInput,
      timestamp: UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    )
  }

  private func resetInputState() {
    inputStateLock.lock()
    hintModeActive = false
    suppressedKeyCodes.removeAll()
    optionWasPressed = false
    tapDetector.cancel()
    inputStateLock.unlock()
  }

  deinit {
    stop()
  }
}
