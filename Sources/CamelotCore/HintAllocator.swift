public struct HintAllocator: Sendable {
  public static let homePositionAlphabet = Array("ASDFGHJKLQWERTYUIOPZXCVBNM")

  private struct OpenPrefix {
    let code: [Character]
    var nextChildIndex: Int
  }

  private let alphabet: [Character]
  private let rank: [Character: Int]

  public init(alphabet: [Character] = Self.homePositionAlphabet) {
    precondition(alphabet.count >= 2, "Hint alphabet needs at least two characters")
    precondition(Set(alphabet).count == alphabet.count, "Hint alphabet must be unique")
    self.alphabet = alphabet
    rank = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
  }

  public func codes(for count: Int) -> [String] {
    guard count > 0 else { return [] }

    var leaves = alphabet.map { [$0] }
    var openPrefixes = [OpenPrefix]()

    // ponytail: O(n²) is fine for visual hint counts; use a priority queue only
    // if measured screens make allocation a bottleneck.
    while leaves.count < count {
      if let prefixIndex = openPrefixes.indices
        .filter({ openPrefixes[$0].nextChildIndex < alphabet.count })
        .min(by: { preferred(openPrefixes[$0].code, over: openPrefixes[$1].code) })
      {
        let childIndex = openPrefixes[prefixIndex].nextChildIndex
        leaves.append(openPrefixes[prefixIndex].code + [alphabet[childIndex]])
        openPrefixes[prefixIndex].nextChildIndex += 1
        continue
      }

      let shallowestDepth = leaves.lazy.map(\.count).min()!
      let leafIndex = leaves.indices
        .filter { leaves[$0].count == shallowestDepth }
        .max { preferred(leaves[$0], over: leaves[$1]) }!
      let prefix = leaves.remove(at: leafIndex)

      leaves.append(prefix + [alphabet[0]])
      leaves.append(prefix + [alphabet[1]])
      openPrefixes.append(OpenPrefix(code: prefix, nextChildIndex: 2))
    }

    return leaves
      .sorted {
        if $0.count != $1.count { return $0.count < $1.count }
        return preferred($0, over: $1)
      }
      .map { String($0) }
  }

  private func preferred(_ lhs: [Character], over rhs: [Character]) -> Bool {
    for (left, right) in zip(lhs, rhs) where left != right {
      return rank[left, default: .max] < rank[right, default: .max]
    }
    return lhs.count < rhs.count
  }
}
