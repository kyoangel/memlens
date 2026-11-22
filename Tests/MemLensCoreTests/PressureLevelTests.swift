import Testing
@testable import MemLensCore

@Suite struct PressureLevelTests {
    @Test func mapsKernelValues() {
        #expect(PressureLevel(sysctlValue: 1) == .normal)
        #expect(PressureLevel(sysctlValue: 2) == .warning)
        #expect(PressureLevel(sysctlValue: 4) == .critical)
    }

    @Test func unknownKernelValueIsNormal() {
        #expect(PressureLevel(sysctlValue: 0) == .normal)
        #expect(PressureLevel(sysctlValue: 99) == .normal)
    }

    @Test func levelsAreOrdered() {
        #expect(PressureLevel.normal < .warning)
        #expect(PressureLevel.warning < .critical)
    }
}
