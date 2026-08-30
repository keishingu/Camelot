# Camelot Product Requirements and MVP Architecture

- Status: Approved for MVP implementation
- Target: macOS 26+
- Last updated: 2026-08-30

## 1. Product goal

Camelot is a native macOS utility that lets people operate the GUI without
moving a hand to the mouse. A short trigger opens a temporary hint layer over
the actionable controls in the focused window. Typing a hint focuses or
activates that control.

The product principle is **Office KeyTips everywhere on macOS**.

Camelot is independent from Rinvio (formerly QuickDraw):

- Rinvio maps known, high-frequency actions to predetermined shortcuts.
- Camelot generates temporary shortcuts for the GUI that is visible now.

Camelot is not a Vim mode and does not add `hjkl`, text objects, OCR, screen
capture, AI UI interpretation, mouse gestures, or large sets of per-app rules.

## 2. Repository and environment findings

The Camelot directory was empty before implementation started. The reference
Rinvio repository uses Swift, SwiftUI, AppKit, CoreGraphics, and an active
`CGEventTap`. Its nonactivating `NSPanel`, permission checks, fail-open input
handling, and event-tap lifecycle are useful patterns, but the products do not
share source or runtime integration.

Investigation environment:

- macOS 26.6
- Xcode 26.3
- macOS 26.2 SDK
- Swift 6.2.4

The macOS 26 SDK provides `NSGlassEffectView` Regular and Clear styles and
SwiftUI's `glassEffect` APIs.

## 3. Feasibility

### Confirmed by public APIs and the local SDK

- `AXUIElementCreateApplication` can create the AX root for a foreground PID.
- `AXFocusedWindow`, roles, subroles, position, size, enabled state, focus,
  selected state, values, children, and visible children can be queried.
- Supported actions are obtained with `AXUIElementCopyActionNames`.
- `AXPress` and other advertised actions can be requested with
  `AXUIElementPerformAction`.
- A writable `AXFocused` attribute can focus text controls.
- An active `CGEventTap` can observe and conditionally suppress keyboard input.
- A borderless nonactivating `NSPanel` can display a click-through overlay.
- Chrome and Safari expose web accessibility trees to macOS accessibility
  clients, subject to the page and browser implementation.

The raw AX API has no general `AXFrame` attribute. Camelot constructs a frame
from `AXPosition` and `AXSize`. AX coordinates have a top-left origin and need
conversion to AppKit's screen coordinates.

### Must be validated by spikes

- Clean-user Accessibility and Input Monitoring permission combinations.
- Option tap with Option+Arrow, Option+character, IME, Sticky Keys, and mouse.
- Full-screen, Spaces, Stage Manager, Mission Control, and display changes.
- Chrome, Safari, Slack, and VS Code tree completeness and first-scan latency.
- Hundreds to thousands of AX nodes in Electron and web applications.
- Which AX notifications are reliably emitted by each target application.

### Best effort or difficult

- Controls that an application does not expose through Accessibility.
- Canvas-only web applications and incorrectly authored ARIA.
- Exact occlusion by unrelated windows; AX frame alone is insufficient.
- Secure Input and protected system contexts.
- Pixel-perfect global hint collision avoidance.

## 4. Distribution constraints

The current MVP controls other applications with AX APIs. Mac App Store apps
must be sandboxed, while Apple documents that an app controlling another app
cannot be sandboxed. Rinvio also received an App Review rejection for its Input
Monitoring and Accessibility use.

No distribution channel is permanently selected yet. Technical spikes use a
non-sandboxed build with a stable identity. Current options are:

- Developer ID + Hardened Runtime + notarization: best technical fit.
- Homebrew Cask: a later delivery channel for the same signed artifact.
- Mac App Store: requires a materially reduced product or a future policy/API
  change; it is not assumed viable for this MVP.

## 5. Functional requirements

### 5.1 Permissions

- Explain Accessibility before requesting it.
- Request Input Monitoring only if the event-tap spike proves it necessary.
- Recheck permissions when Camelot becomes active and before every session.
- If permission is missing or revoked, hide overlays and pass all input through.
- Provide a System Settings recovery path without repeatedly prompting.

### 5.2 Trigger and input

- The first candidate is a short Option tap, completed on release.
- Option events themselves always pass through.
- Any intervening key, modifier, mouse click, or scroll cancels the tap.
- Option+Arrow, Option+character, special-character input, and system shortcuts
  must retain their normal behavior.
- Bare `F` is not a default because it would break ordinary global typing.
- During Hint Mode, Camelot may consume hint characters and matching key-up
  events. Escape cancels immediately and Backspace removes one prefix letter.
- Event-tap timeout or permission loss cancels the session and fails open.

### 5.3 AX traversal

- Resolve the frontmost process with `NSWorkspace` and scan its focused window.
- Include attached sheets, dialogs, and menus that are currently visible.
- Prefer `AXVisibleChildren`, falling back to `AXChildren`.
- Traverse iteratively with node, depth, and elapsed-time safety budgets.
- Scan only when Hint Mode starts. Do not poll or retain a cross-session cache.
- Batch attributes where it reduces AX IPC.
- Use AXObserver and workspace notifications to invalidate a session, not as a
  reason to maintain a continuously synchronized mirror of the AX tree.
- Do not request text-field values or document contents.

An actionable candidate must be enabled, have a non-empty on-screen frame, and
either advertise a supported action or expose a safe focusable input role.
Containers, static text, and decorative images are excluded. Nested duplicate
controls are removed best effort.

### 5.4 Hint allocation

Initial alphabet, ordered by keyboard ergonomics:

`A S D F G H J K L Q W E R T Y U I O P Z X C V B N M`

Codes are prefix-free leaves in an ordered 26-way tree:

- Up to 26 candidates use one character.
- When more leaves are needed, a low-priority leaf becomes a prefix and gains
  children.
- The same rule extends to three or more characters.
- An exact leaf executes immediately; an internal prefix only filters.
- No executable code is the prefix of another executable code.

Candidates are ordered deterministically by display, top-to-bottom, then
left-to-right. Allocation remains stable for the lifetime of a session. Usage
history and adaptive ranking are outside the MVP.

### 5.5 Rendering

- Use one borderless, nonactivating, click-through panel per display.
- Start with `.statusBar` level and the proven combination of
  `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.transient`, and `.ignoresCycle`.
- Compare macOS 26 `canJoinAllApplications` during the overlay spike.
- Use points, not pixels, and align to each display's backing scale.
- Place a hint above-leading, inside-leading, below-leading, or trailing of its
  target, clamp it to the screen, then choose the placement with least overlap.
- Greedy collision avoidance is sufficient for MVP; never silently remove a
  candidate because every placement overlaps.
- Filtering hides nonmatches but does not reposition surviving hints.
- Use quiet, noninteractive Regular Liquid Glass. Clear is not automatically
  selected because Camelot does not inspect the background with screen capture.
- Respect Reduce Motion, Reduce Transparency, and Increase Contrast.

### 5.6 AX execution policy

| Control | Action |
| --- | --- |
| Button, link, checkbox, radio, menu item | `AXPress` |
| Tab | `AXPress`, then set `AXSelected` only if supported and settable |
| Toolbar item | Child button or advertised `AXPress` |
| Pop-up button | `AXPress` or advertised show-menu action |
| Text field, search field, text area | Set `AXFocused = true` |
| Combo box | Focus first, then advertised action if needed |
| Slider and stepper | Focus only in MVP |
| Window | Not a hint target; do not use `AXRaise` in MVP |

Before execution, revalidate PID, focused window, element validity, enabled
state, action, and frame. Do not automatically retry a non-idempotent action
after `kAXErrorCannotComplete`, because the operation may already have run.

Coordinate-based mouse clicks are not part of the first MVP. Add them only if
measured AX gaps prevent the target application success gate.

### 5.7 Cancellation and errors

- Cancel on Escape, app switch, focused-window change, external focus change,
  display configuration change, or mouse input.
- Discard results from a stale scan using a session generation identifier.
- If an element disappears before execution, do nothing and close the overlay.
- If no candidates are found, display brief nonmodal feedback.
- Mission Control behavior is finalized by spike; stale hints must never remain.

## 6. State machine

```text
Idle
  -> TriggerDetected
  -> ScanningAX
  -> ShowingHints
  -> FilteringHints
  -> Executing
  -> Idle
```

Transitions and exceptional paths:

- `TriggerDetected` returns to `Idle` when another input arrives or the hold
  timeout expires.
- `ScanningAX` returns to `Idle` on timeout, no candidates, cancellation, or a
  stale generation.
- `ShowingHints` moves to `FilteringHints` for an internal prefix and directly
  to `Executing` for a leaf.
- `FilteringHints` supports further input and Backspace; invalid characters are
  rejected without changing the prefix.
- Any active state can move through `Cancelling` to `Idle`.
- Permission loss moves to `PermissionBlocked`; restoring permission returns to
  `Idle`, never directly to an old session.

## 7. MVP architecture

```text
CamelotApp
    -> AppCoordinator (@MainActor state machine)
        -> KeyboardController (CGEventTap)
        -> PermissionService
        -> AccessibilityScanner (serial AX traversal)
        -> AccessibilityActionExecutor (serial AX execution)
        -> HintAllocator (pure logic)
        -> OverlayController (one NSPanel per display)
            -> HintOverlayView (SwiftUI)
```

The scanner returns immutable candidate snapshots plus the AX references needed
for execution. Scanning and execution stay in two small concrete services; no
backend protocol or factory is introduced for the MVP.

The event-tap callback does no AX work and no rendering. AX IPC runs on a serial
worker. UI and session state stay on the main actor.

## 8. MVP scope and success gate

Included:

- macOS 26 native app with no third-party dependencies.
- Permission onboarding and diagnostics.
- Option tap and a fallback chord if required by spike.
- Focused-window AX scanning.
- Core controls, prefix hints, filtering, Escape, Backspace, AXPress, and focus.
- Stale-element protection, multi-display overlays, Spaces, and full-screen.

Required target groups:

1. Finder
2. System Settings
3. Safari or Chrome
4. Slack or VS Code

For each group, the sequence `Option -> hints -> key -> AXPress/focus -> exit`
must succeed 20 consecutive times. TextEdit validates text focus and preservation
of Option-based text entry. Notion and Office are best effort and not release
gates.

Excluded from MVP:

- Browser extension backend and speculative backend protocols.
- Per-app adapters, OCR, screen capture, AI interpretation, Vim modes.
- Cross-session AX cache and adaptive hint learning.
- Exact global collision optimization and coordinate-click fallback.
- Billing, updater, and final distribution-channel work.

## 9. Performance and privacy requirements

Initial targets, subject to spike measurements:

- Event-tap callback under 1 ms.
- Native trigger-to-hints p95 under 350 ms.
- Electron/browser trigger-to-hints p95 under 800 ms.
- Prefix-to-redraw p95 under 50 ms.
- No AX polling and near-zero CPU use while idle.
- No main-thread AX work over a frame budget.
- Provisional scan stop at 5,000 nodes or 750 ms; never freeze the UI.

Privacy constraints:

- No screen capture, OCR, clipboard reading, or network traffic.
- Do not persist keystrokes, AX values, labels, document text, or AX references.
- Keep only role, frame, supported action, and ephemeral identity needed for the
  active session.
- Camelot's own settings UI must be accessible with VoiceOver.

## 10. Spike order

1. Permission matrix on a clean user account.
2. Focused application/window retrieval.
3. Actionable extraction in Finder and System Settings.
4. AXPosition/AXSize conversion on Retina and multiple displays.
5. AXPress and text-field focus.
6. Option tap and Option combination preservation.
7. Nonactivating overlay across Spaces and full-screen.
8. Chrome, Safari, Slack, and VS Code tree inspection.
9. Hundreds-to-thousands-of-nodes traversal benchmark.
10. Invalidation, hint allocation, collision, and Glass rendering checks.

## 11. Acceptance criteria

- Option tap activates 20/20 times; 100 tested non-tap Option combinations cause
  zero false activations and retain normal behavior.
- Finder, System Settings, one browser, and one Electron app pass the 20-run
  end-to-end gate.
- Disabled, zero-size, and off-screen elements do not receive hints.
- One to 1,000 generated hints are unique and prefix-free; up to 26 use one key.
- Escape closes the overlay within 50 ms and mouse input is never stolen.
- App, window, element, or display changes cannot execute a stale target.
- Two displays, Retina, a full-screen app, and a Space switch leave no stale
  panel and place hints within 4 points of the intended anchor.
- Permission denial and revocation always fail open.
- No key, control value, or document content is persisted or transmitted.

## 12. Decisions still open

Must be decided by spikes before the full vertical slice:

- Option tap as the default and its maximum duration.
- Exact TCC permissions needed by the active filtering tap.
- Physical key positions versus logical characters for JIS, Dvorak, and IME.
- First-level menu bar inclusion.
- Maximum renderable actionable count and overflow UX.
- Whether measured AX gaps justify coordinate-click fallback.

Can be tuned during implementation:

- AX timeout and scan budget.
- Layout-notification debounce.
- Hint padding, tint, collision gap, and selection feedback.
- `canJoinAllApplications` versus the established collection behavior.
- Which browser and Electron app become the required representatives.

## 13. Implementation phases

1. Pure hint allocation and a runnable AX/Option diagnostic vertical slice.
2. Permission onboarding and the complete state machine.
3. AX session ownership, invalidation, and execution.
4. Multi-display AppKit overlay with SwiftUI hints.
5. Target-app compatibility and performance hardening.
6. Signed/notarized build validation and distribution decision.

## 14. Current diagnostic build

The first implementation slice provides:

- Pure, tested prefix-free hint allocation.
- Pure, tested Option tap state detection with a 300 ms provisional limit.
- Pure, tested AX-to-AppKit screen coordinate conversion.
- A listen-only `CGEventTap` that never suppresses input.
- Focused-window AX traversal with 5,000-node and 750 ms safety limits.
- A diagnostic SwiftUI window and menu bar status showing permission and scan
  counts without displaying or persisting control labels or values.
- A non-sandboxed local `.app` bundle with an ad-hoc signature for manual TCC
  validation. Developer ID signing is intentionally deferred.

Developer commands:

```sh
swift test --disable-sandbox
./Scripts/build-app.sh debug
open .build/Camelot.app
```

The first manual run must grant Accessibility and, if requested by macOS, Input
Monitoring. Run the app from the same `.build/Camelot.app` path while testing so
TCC identity and path do not change unnecessarily.
