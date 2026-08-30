import CoreGraphics

public struct ScreenCoordinateConverter: Sendable {
  private let primaryScreenMaxY: CGFloat

  public init(primaryScreenMaxY: CGFloat) {
    self.primaryScreenMaxY = primaryScreenMaxY
  }

  public func appKitFrame(fromAccessibilityFrame frame: CGRect) -> CGRect {
    CGRect(
      x: frame.origin.x,
      y: primaryScreenMaxY - frame.maxY,
      width: frame.width,
      height: frame.height
    )
  }
}
