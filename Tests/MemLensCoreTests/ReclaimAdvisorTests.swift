import Foundation
import Testing
@testable import MemLensCore

@Suite struct ReclaimAdvisorTests {
    let me: Int32 = 999

    func app(_ name: String, pid: Int32, bytes: UInt64, policy: AppActivationPolicy = .regular,
             frontmost: Bool = false, dir: String = "/Applications")
        -> (group: ProcessGroup, running: RunningApp) {
        let bundle = "\(dir)/\(name).app"
        return (
            ProcessGroup(id: bundle, kind: .app, name: name, bundlePath: bundle, pids: [pid], footprint: bytes),
            RunningApp(pid: pid, bundlePath: bundle, name: name, policy: policy, isFrontmost: frontmost)
        )
    }

    func advise(_ items: [(group: ProcessGroup, running: RunningApp)],
                idle: [String: TimeInterval] = [:],
                policy: ReclaimPolicy = .default) -> [ReclaimCandidate] {
        ReclaimAdvisor.advise(
            groups: items.map(\.group),
            apps: items.map(\.running),
            idleSeconds: { idle[$0] },
            selfPid: me,
            policy: policy)
    }

    @Test func ranksUnknownIdleBySizeOnly() {
        let result = advise([
            app("Small", pid: 1, bytes: 1 * GB),
            app("Big", pid: 2, bytes: 3 * GB),
            app("Medium", pid: 3, bytes: 2 * GB),
        ])
        #expect(result.map(\.name) == ["Big", "Medium", "Small"])
        #expect(result.allSatisfy { $0.idleSeconds == nil })
    }

    @Test func longIdleBeatsEqualSizedUnknown() {
        let result = advise(
            [app("Unknown", pid: 1, bytes: 1 * GB), app("Stale", pid: 2, bytes: 1 * GB)],
            idle: ["/Applications/Stale.app": 3.0 * 3600])
        #expect(result.map(\.name) == ["Stale", "Unknown"])
    }

    @Test func unknownIsNotTreatedAsLongIdle() {
        // Unknown 2GB must beat a 1GB app that was used 10 minutes ago.
        let result = advise(
            [app("Unknown", pid: 1, bytes: 2 * GB), app("Recent", pid: 2, bytes: 1 * GB)],
            idle: ["/Applications/Recent.app": 600])
        #expect(result.map(\.name) == ["Unknown", "Recent"])
    }

    @Test func recentlyUsedAppsAreNotSuggested() {
        let result = advise(
            [app("JustUsed", pid: 1, bytes: 4 * GB)],
            idle: ["/Applications/JustUsed.app": 30])
        #expect(result.isEmpty)
    }

    @Test func neverSuggestsFrontmostSystemMenuBarOrSelf() {
        let result = advise([
            app("Front", pid: 1, bytes: 4 * GB, frontmost: true),
            app("Safari", pid: 2, bytes: 4 * GB, dir: "/System/Cryptexes/App/System/Applications"),
            app("Finder", pid: 3, bytes: 4 * GB, dir: "/System/Library/CoreServices"),
            app("Bartender", pid: 4, bytes: 4 * GB, policy: .accessory),
            app("Daemon", pid: 5, bytes: 4 * GB, policy: .prohibited),
            app("MemLens", pid: me, bytes: 4 * GB),
            app("Keep", pid: 6, bytes: 4 * GB),
        ])
        #expect(result.map(\.name) == ["Keep"])
    }

    @Test func skipsGroupsWithoutARunningGuiApp() {
        let orphan = ProcessGroup(id: "/Applications/Ghost.app", kind: .app, name: "Ghost",
                                  bundlePath: "/Applications/Ghost.app", pids: [77], footprint: 4 * GB)
        let python = ProcessGroup(id: "pid:50", kind: .python, name: "Python", pids: [50], footprint: 11 * GB)
        let result = ReclaimAdvisor.advise(groups: [orphan, python], apps: [], idleSeconds: { _ in nil }, selfPid: me)
        #expect(result.isEmpty)
    }

    @Test func skipsSmallAppsAndHonorsLimit() {
        var policy = ReclaimPolicy.default
        policy.limit = 2
        let result = advise([
            app("Tiny", pid: 1, bytes: 100 * MB),
            app("A", pid: 2, bytes: 1 * GB),
            app("B", pid: 3, bytes: 2 * GB),
            app("C", pid: 4, bytes: 3 * GB),
        ], policy: policy)
        #expect(result.map(\.name) == ["C", "B"])
    }

    @Test func candidateCarriesPidAndWholeAppFootprint() {
        let result = advise([app("Chrome", pid: 42, bytes: 3 * GB)])
        #expect(result == [ReclaimCandidate(id: "/Applications/Chrome.app", name: "Chrome", pid: 42,
                                            footprint: 3 * GB, idleSeconds: nil)])
    }
}
