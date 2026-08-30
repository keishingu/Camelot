public enum HintMatch: Equatable, Sendable {
  case noMatch
  case filtering(prefix: String, matchingIndices: [Int])
  case selected(index: Int)
}

public func matchHintCodes(
  _ codes: [String],
  currentPrefix: String,
  input: Character
) -> HintMatch {
  let prefix = currentPrefix + String(input).uppercased()
  let matchingIndices = codes.indices.filter { codes[$0].hasPrefix(prefix) }

  guard !matchingIndices.isEmpty else { return .noMatch }
  if matchingIndices.count == 1, codes[matchingIndices[0]] == prefix {
    return .selected(index: matchingIndices[0])
  }
  return .filtering(prefix: prefix, matchingIndices: matchingIndices)
}
