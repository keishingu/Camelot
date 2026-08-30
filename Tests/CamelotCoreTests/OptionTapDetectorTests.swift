import Testing
@testable import CamelotCore

@Suite("Option tap detection")
struct OptionTapDetectorTests {
  @Test("A short press and release triggers")
  func shortTap() {
    var detector = OptionTapDetector(maximumDurationNanoseconds: 300)

    let downTriggered = detector.optionChanged(.left, isDown: true, timestamp: 100)
    let upTriggered = detector.optionChanged(.left, isDown: false, timestamp: 250)

    #expect(!downTriggered)
    #expect(upTriggered)
  }

  @Test("Other input cancels the candidate")
  func cancellation() {
    var detector = OptionTapDetector(maximumDurationNanoseconds: 300)

    _ = detector.optionChanged(.left, isDown: true, timestamp: 100)
    detector.cancel()
    let triggered = detector.optionChanged(.left, isDown: false, timestamp: 200)

    #expect(!triggered)
  }

  @Test("Long holds and mismatched Option keys do not trigger")
  func rejectedGestures() {
    var detector = OptionTapDetector(maximumDurationNanoseconds: 300)

    _ = detector.optionChanged(.left, isDown: true, timestamp: 100)
    let longHoldTriggered = detector.optionChanged(.left, isDown: false, timestamp: 401)

    _ = detector.optionChanged(.left, isDown: true, timestamp: 500)
    let mismatchedKeyTriggered = detector.optionChanged(
      .right,
      isDown: false,
      timestamp: 600
    )

    #expect(!longHoldTriggered)
    #expect(!mismatchedKeyTriggered)
  }
}
