import Testing
@testable import CamelotCore

@Suite("Hint allocation")
struct HintAllocatorTests {
  private let allocator = HintAllocator()

  @Test("Empty input has no hints")
  func empty() {
    #expect(allocator.codes(for: 0).isEmpty)
  }

  @Test("Up to one alphabet uses one character")
  func singleCharacterHints() {
    let codes = allocator.codes(for: 26)

    #expect(codes.count == 26)
    #expect(codes.allSatisfy { $0.count == 1 })
    #expect(codes.first == "A")
    #expect(codes.last == "M")
  }

  @Test("Twenty-seven hints retain twenty-five short codes")
  func mixedLengths() {
    let codes = allocator.codes(for: 27)

    #expect(codes.filter { $0.count == 1 }.count == 25)
    #expect(codes.filter { $0.count == 2 }.count == 2)
    expectPrefixFree(codes)
  }

  @Test("Large allocations remain deterministic and prefix-free")
  func largeAllocation() {
    let codes = allocator.codes(for: 1_000)

    #expect(codes.count == 1_000)
    #expect(Set(codes).count == codes.count)
    #expect(codes == allocator.codes(for: 1_000))
    expectPrefixFree(codes)
  }

  private func expectPrefixFree(_ codes: [String]) {
    for code in codes {
      #expect(!codes.contains { $0 != code && $0.hasPrefix(code) })
    }
  }
}
