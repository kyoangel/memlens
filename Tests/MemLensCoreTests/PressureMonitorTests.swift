import Testing
@testable import MemLensCore

@Suite struct PressureMonitorTests {
    @Test func currentReadsThroughTheReader() {
        let fake = FakeSystemReader()
        let monitor = PressureMonitor(reader: fake)
        #expect(monitor.current == .normal)
        fake.pressure = .critical
        #expect(monitor.current == .critical)
    }

    @Test func liveMonitorStartsAndStopsCleanly() {
        let monitor = PressureMonitor(reader: LiveSystemReader())
        #expect(PressureLevel.allCases.contains(monitor.current))
        monitor.start { _ in }
        monitor.start { _ in }   // restart replaces the old source
        monitor.stop()
        monitor.stop()           // idempotent
    }
}
