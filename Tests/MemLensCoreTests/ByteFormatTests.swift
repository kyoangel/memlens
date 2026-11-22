import Testing
@testable import MemLensCore

@Suite struct ByteFormatTests {
    @Test func formatsGigabytesWithOneDecimal() {
        #expect(ByteFormat.string(3 * GB + 200 * MB) == "3.2 GB")
        #expect(ByteFormat.string(11 * GB) == "11.0 GB")
    }

    @Test func formatsSmallValuesInMegabytes() {
        #expect(ByteFormat.string(850 * MB) == "850 MB")
        #expect(ByteFormat.string(0) == "0 MB")
    }
}
