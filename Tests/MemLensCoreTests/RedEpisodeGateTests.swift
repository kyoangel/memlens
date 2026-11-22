import Testing
@testable import MemLensCore

@Suite struct RedEpisodeGateTests {
    @Test func firesOnceForARedEpisode() {
        var gate = RedEpisodeGate()
        #expect(gate.shouldNotify(for: .critical) == true)
        #expect(gate.shouldNotify(for: .critical) == false)
        #expect(gate.shouldNotify(for: .critical) == false)
    }

    @Test func yellowDoesNotRearm() {
        var gate = RedEpisodeGate()
        #expect(gate.shouldNotify(for: .critical) == true)
        #expect(gate.shouldNotify(for: .warning) == false)
        #expect(gate.shouldNotify(for: .critical) == false)
    }

    @Test func rearmsAfterReturningToGreen() {
        var gate = RedEpisodeGate()
        #expect(gate.shouldNotify(for: .critical) == true)
        #expect(gate.shouldNotify(for: .normal) == false)
        #expect(gate.shouldNotify(for: .critical) == true)
    }

    @Test func neverFiresBelowRed() {
        var gate = RedEpisodeGate()
        #expect(gate.shouldNotify(for: .normal) == false)
        #expect(gate.shouldNotify(for: .warning) == false)
    }
}
