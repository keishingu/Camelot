import AppKit
import CamelotCore
import Combine
import Foundation

@MainActor
final class CamelotAppModel: ObservableObject {
  @Published private(set) var permissions: PermissionSnapshot
  @Published private(set) var status = "Starting Camelot…"
  @Published private(set) var lastScan: AccessibilityScanResult?
  @Published private(set) var isScanning = false
  @Published private(set) var activePrefix = ""

  var roleCounts: [(String, Int)] {
    let grouped = Dictionary(grouping: lastScan?.candidates ?? [], by: \.role)
    return grouped.map { ($0.key, $0.value.count) }.sorted { $0.0 < $1.0 }
  }

  var isHintModeActive: Bool { !sessionHints.isEmpty }

  private struct SessionHint {
    let code: String
    let candidate: AccessibilityCandidate
  }

  private let scanner: any AccessibilityScanning
  private let executor = AccessibilityActionExecutor()
  private let keyboardTrigger: any KeyboardTriggering
  private let overlay = OverlayWindowController()
  private let permissionSnapshot: () -> PermissionSnapshot
  private var sessionHints = [SessionHint]()
  private var scanGeneration = 0
  private var started = false
  private var cancellables = Set<AnyCancellable>()

  init(
    scanner: any AccessibilityScanning = AccessibilityScanner(),
    keyboardTrigger: any KeyboardTriggering = KeyboardTriggerService(),
    permissionSnapshot: @escaping () -> PermissionSnapshot = { PermissionService.current }
  ) {
    self.scanner = scanner
    self.keyboardTrigger = keyboardTrigger
    self.permissionSnapshot = permissionSnapshot
    permissions = permissionSnapshot()

    keyboardTrigger.onOptionTap = { [weak self] in
      self?.showHints()
    }
    keyboardTrigger.onHintCharacter = { [weak self] character in
      self?.acceptHintCharacter(character)
    }
    keyboardTrigger.onBackspace = { [weak self] in
      self?.deleteHintCharacter()
    }
    keyboardTrigger.onCancel = { [weak self] in
      self?.cancelHintSession(message: "Hint Mode cancelled")
    }

    NSWorkspace.shared.notificationCenter
      .publisher(for: NSWorkspace.didActivateApplicationNotification)
      .sink { [weak self] notification in
        guard let self else { return }
        if self.isScanning {
          self.cancelHintSession(message: "Hint Mode cancelled because the app changed")
          return
        }
        guard
          let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication,
          let sessionPID = self.sessionHints.first?.candidate.pid,
          application.processIdentifier != sessionPID
        else { return }
        self.cancelHintSession(message: "Hint Mode cancelled because the app changed")
      }
      .store(in: &cancellables)

    NotificationCenter.default
      .publisher(for: NSApplication.didChangeScreenParametersNotification)
      .sink { [weak self] _ in
        guard self?.isHintModeActive == true else { return }
        self?.cancelHintSession(message: "Hint Mode cancelled because displays changed")
      }
      .store(in: &cancellables)
  }

  func start() {
    guard !started else { return }
    started = true
    permissions = permissionSnapshot()
    startKeyboardTriggerIfPossible()
  }

  func refreshPermissions() {
    permissions = permissionSnapshot()
    let authorized = permissions.accessibility && permissions.inputMonitoring
    if !authorized {
      if isScanning || isHintModeActive {
        cancelHintSession(message: "Hint Mode cancelled because permission changed")
      }
      keyboardTrigger.stop()
    } else if started, !keyboardTrigger.isRunning {
      startKeyboardTriggerIfPossible()
    }
  }

  func requestAccessibility() {
    PermissionService.requestAccessibility()
    refreshPermissions()
    status = permissions.accessibility
      ? "Accessibility granted"
      : "Enable Camelot in Privacy & Security → Accessibility"
  }

  func requestInputMonitoring() {
    PermissionService.requestInputMonitoring()
    refreshPermissions()
    status = permissions.inputMonitoring
      ? "Input Monitoring granted"
      : "Enable Camelot in Privacy & Security → Input Monitoring"
  }

  func scanFrontmostApplication() {
    showHints()
  }

  func showHints() {
    refreshPermissions()
    guard permissions.accessibility else {
      status = "Accessibility permission is required before scanning"
      return
    }
    guard keyboardTrigger.isRunning else {
      status = "Input Monitoring is required before showing hints"
      return
    }
    cancelHintSession(message: nil)
    let generation = scanGeneration
    isScanning = true
    status = "Scanning the focused window…"

    scanner.scanFrontmostApplication { [weak self] result in
      guard let self, generation == self.scanGeneration else { return }
      self.isScanning = false

      switch result {
      case .success(let scan):
        self.lastScan = scan
        self.beginHintSession(with: scan)
      case .failure(let error):
        self.status = error.localizedDescription
      }
    }
  }

  private func beginHintSession(with scan: AccessibilityScanResult) {
    let candidates = scan.candidates.sorted {
      if abs($0.frame.maxY - $1.frame.maxY) > 2 {
        return $0.frame.maxY > $1.frame.maxY
      }
      return $0.frame.minX < $1.frame.minX
    }
    guard !candidates.isEmpty else {
      status = "\(scan.applicationName): no actionable elements found"
      return
    }

    let codes = HintAllocator().codes(for: candidates.count)
    sessionHints = zip(codes, candidates).map {
      SessionHint(code: $0.0, candidate: $0.1)
    }
    activePrefix = ""
    keyboardTrigger.setHintModeActive(true)
    renderHints()

    let milliseconds = Int((scan.duration * 1_000).rounded())
    status = "\(scan.applicationName): \(candidates.count) hints in \(milliseconds) ms"
  }

  private func acceptHintCharacter(_ character: Character) {
    let codes = sessionHints.map(\.code)
    switch matchHintCodes(codes, currentPrefix: activePrefix, input: character) {
    case .noMatch:
      status = "No hint matches \(activePrefix + String(character))"
    case .filtering(let prefix, _):
      activePrefix = prefix
      renderHints()
    case .selected(let index):
      execute(sessionHints[index])
    }
  }

  private func deleteHintCharacter() {
    guard !activePrefix.isEmpty else { return }
    activePrefix.removeLast()
    renderHints()
  }

  private func execute(_ hint: SessionHint) {
    keyboardTrigger.setHintModeActive(false)
    overlay.hide()
    sessionHints.removeAll()
    lastScan = nil
    activePrefix = ""
    status = "Executing \(hint.code)…"

    executor.execute(hint.candidate) { [weak self] result, diagnostics in
      switch result {
      case .success:
        self?.status = "Executed \(hint.code) · \(diagnostics)"
      case .failure(let error):
        self?.status = "\(error.localizedDescription) · \(diagnostics)"
      }
    }
  }

  private func renderHints() {
    let items = sessionHints.compactMap { hint -> HintOverlayItem? in
      guard hint.code.hasPrefix(activePrefix) else { return nil }
      return HintOverlayItem(
        id: hint.candidate.id,
        code: hint.code,
        frame: hint.candidate.frame,
        typedCount: activePrefix.count
      )
    }
    overlay.show(items)
  }

  private func cancelHintSession(message: String?) {
    scanGeneration += 1
    isScanning = false
    keyboardTrigger.setHintModeActive(false)
    overlay.hide()
    sessionHints.removeAll()
    lastScan = nil
    activePrefix = ""
    if let message { status = message }
  }

  private func startKeyboardTriggerIfPossible() {
    guard permissions.accessibility, permissions.inputMonitoring else {
      status = "Accessibility and Input Monitoring are required"
      return
    }
    status = keyboardTrigger.start()
      ? "Tap Option to show hints"
      : "The keyboard event tap could not start"
  }
}
