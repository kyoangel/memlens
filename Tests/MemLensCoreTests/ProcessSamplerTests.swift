import Foundation
import Testing
@testable import MemLensCore

@Suite struct ProcessSamplerTests {
    @Test func returnsReadableProcesses() {
        let fake = FakeSystemReader()
        fake.add(pid: 10, path: "/Applications/Foo.app/Contents/MacOS/Foo", footprint: 300 * MB)
        fake.add(pid: 11, path: "/usr/bin/python3", footprint: 2 * GB)

        let sample = ProcessSampler.sample(reader: fake)

        #expect(sample.processes.map(\.pid) == [10, 11])
        #expect(sample.processes[1].footprint == 2 * GB)
        #expect(sample.processes[1].executableName == "python3")
        #expect(sample.unreadableCount == 0)
    }

    @Test func skipsUnreadableProcessesAndCountsThem() {
        let fake = FakeSystemReader()
        fake.add(pid: 1, path: "/sbin/launchd", footprint: nil)   // root-owned: no rusage
        fake.add(pid: 2, path: nil, footprint: 5 * MB)            // exited mid-scan: no path
        fake.add(pid: 3, path: "/bin/zsh", footprint: 4 * MB)

        let sample = ProcessSampler.sample(reader: fake)

        #expect(sample.processes.map(\.pid) == [3])
        #expect(sample.unreadableCount == 2)
    }

    @Test func liveSampleContainsOwnProcess() {
        let sample = ProcessSampler.sample(reader: LiveSystemReader())
        let mine = sample.processes.first { $0.pid == getpid() }
        #expect(mine != nil)
        #expect((mine?.footprint ?? 0) > 0)
    }
}
