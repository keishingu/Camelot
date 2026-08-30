import Testing
@testable import CamelotCore

@Suite("Hint matching")
struct HintMatcherTests {
  @Test("A complete leaf selects its candidate")
  func selectsLeaf() {
    #expect(matchHintCodes(["A", "S"], currentPrefix: "", input: "a") == .selected(index: 0))
  }

  @Test("A shared prefix filters and an invalid key leaves the session unchanged")
  func filtersPrefix() {
    let codes = ["AA", "AS", "S"]

    #expect(
      matchHintCodes(codes, currentPrefix: "", input: "A")
        == .filtering(prefix: "A", matchingIndices: [0, 1])
    )
    #expect(matchHintCodes(codes, currentPrefix: "A", input: "Z") == .noMatch)
  }
}
