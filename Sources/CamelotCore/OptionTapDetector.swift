public struct OptionTapDetector: Sendable {
  public enum Key: Sendable {
    case left
    case right
  }

  private struct Candidate: Sendable {
    let key: Key
    let downTimestamp: UInt64
  }

  private let maximumDuration: UInt64
  private var candidate: Candidate?

  public init(maximumDurationNanoseconds: UInt64 = 300_000_000) {
    maximumDuration = maximumDurationNanoseconds
  }

  public mutating func optionChanged(
    _ key: Key,
    isDown: Bool,
    timestamp: UInt64
  ) -> Bool {
    if isDown {
      guard candidate == nil else {
        candidate = nil
        return false
      }
      candidate = Candidate(key: key, downTimestamp: timestamp)
      return false
    }

    guard let candidate, candidate.key == key else {
      self.candidate = nil
      return false
    }
    self.candidate = nil
    guard timestamp >= candidate.downTimestamp else { return false }
    return timestamp - candidate.downTimestamp <= maximumDuration
  }

  public mutating func cancel() {
    candidate = nil
  }
}
