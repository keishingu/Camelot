import ApplicationServices
@testable import Camelot
import XCTest

final class AccessibilityScannerTests: XCTestCase {
  func testChildTraversalPrefersNavigationOrderWithoutExtraChromiumFallbacks() {
    XCTAssertEqual(
      AccessibilityScanner.childAttributePriority,
      ["AXChildrenInNavigationOrder", kAXVisibleChildrenAttribute, kAXChildrenAttribute]
    )
  }

  func testSemanticChildOutranksGenericPressWrapper() {
    let element = AXUIElementCreateSystemWide()
    let generic = candidate(role: "AXGroup", action: .press, element: element)
    let semantic = candidate(role: "AXButton", action: .click, element: element)

    let scanner = AccessibilityScanner()
    XCTAssertLessThan(scanner.candidatePriority(semantic), scanner.candidatePriority(generic))
  }

  func testRowButtonUsesClickWithoutChangingRegularButtons() {
    let scanner = AccessibilityScanner()
    let press = Set([kAXPressAction as String])

    XCTAssertEqual(
      scanner.preferredAction(
        role: "AXButton",
        actions: press,
        canFocus: false,
        frame: CGRect(x: 0, y: 0, width: 300, height: 40)
      ),
      .click
    )
    XCTAssertEqual(
      scanner.preferredAction(
        role: "AXButton",
        actions: press,
        canFocus: false,
        frame: CGRect(x: 0, y: 0, width: 100, height: 40)
      ),
      .press
    )
  }

  private func candidate(
    role: String,
    action: CandidateAction,
    element: AXUIElement
  ) -> AccessibilityCandidate {
    AccessibilityCandidate(
      id: 0,
      pid: 0,
      role: role,
      subrole: nil,
      frame: .zero,
      activationPoint: .zero,
      action: action,
      element: element,
      window: element
    )
  }
}
