import CoreGraphics
import Testing
@testable import CamelotCore

@Suite("Screen coordinate conversion")
struct ScreenCoordinateConverterTests {
  private let converter = ScreenCoordinateConverter(primaryScreenMaxY: 900)

  @Test("Converts top-left AX coordinates to bottom-left AppKit coordinates")
  func primaryDisplay() {
    let frame = converter.appKitFrame(
      fromAccessibilityFrame: CGRect(x: 100, y: 100, width: 80, height: 20)
    )

    #expect(frame == CGRect(x: 100, y: 780, width: 80, height: 20))
  }

  @Test("Preserves global negative and extended display coordinates")
  func extendedDisplays() {
    let frame = converter.appKitFrame(
      fromAccessibilityFrame: CGRect(x: -500, y: -200, width: 100, height: 40)
    )

    #expect(frame == CGRect(x: -500, y: 1_060, width: 100, height: 40))
  }
}
