import Foundation
import Testing
@testable import MemLensCore

@MainActor
@Suite struct AppStateTests {
    static let fluxFile =
        "/Users/me/.cache/huggingface/hub/models--black-forest-labs--FLUX.1-schnell/snapshots/abc/w.safetensors"

    /// A world with Chrome (1 main + 3 helpers), Safari (front), and a FLUX python process.
    func makeWorld() -> FakeSystemReader {
        let fake = FakeSystemReader()
        let chrome = "/Applications/Google Chrome.app"
        fake.add(pid: 100, path: chrome + "/Contents/MacOS/Google Chrome", footprint: 600 * MB)
        for i in 0..<3 {
            fake.add(pid: Int32(101 + i),
                     path: chrome + "/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/h",
                     footprint: 500 * MB)
        }
        fake.add(pid: 200, path: "/Applications/Safari.app/Contents/MacOS/Safari", footprint: 2 * GB)
        fake.add(pid: 300, path: "/opt/homebrew/bin/python3", footprint: 11 * GB,
                 args: ["python3", "gen.py"], files: [Self.fluxFile])
        fake.apps = [
            RunningApp(pid: 100, bundlePath: chrome, name: "Google Chrome", policy: .regular, isFrontmost: false),
            RunningApp(pid: 200, bundlePath: "/Applications/Safari.app", name: "Safari", policy: .regular, isFrontmost: true),
        ]
        return fake
    }

    func makeState(_ fake: FakeSystemReader,
                   actions: FakeAppActions = FakeAppActions(),
                   alertEnabled: @escaping @MainActor () -> Bool = { true },
                   onAlert: @escaping @MainActor (String, String) -> Void = { _, _ in },
                   sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) -> AppState {
        AppState(
            reader: fake,
            terminator: AppTerminator(actions: actions, sleep: { _ in }),
            selfPid: 999,
            isAlertEnabled: alertEnabled,
            sendAlert: onAlert,
            sleep: sleep)
    }

    @Test func cadenceIsThreeSecondsGreenAndOneSecondOtherwise() {
        #expect(AppState.refreshInterval(for: .normal) == .seconds(3))
        #expect(AppState.refreshInterval(for: .warning) == .seconds(1))
        #expect(AppState.refreshInterval(for: .critical) == .seconds(1))
    }

    @Test func greenAndMenuClosedOnlyUpdatesTheIcon() {
        let fake = makeWorld()
        let state = makeState(fake)
        state.refresh()
        #expect(state.level == .normal)
        #expect(fake.listPidsCallCount == 0)
        #expect(state.groups.isEmpty)
    }

    @Test func openingTheMenuRunsTheFullPipeline() {
        let fake = makeWorld()
        let state = makeState(fake)
        state.setMenuOpen(true)

        #expect(fake.listPidsCallCount == 1)
        let names = state.groups.map(\.displayName)
        #expect(names.contains("Python · FLUX.1-schnell"))
        let chrome = state.groups.first { $0.name == "Google Chrome" }
        #expect(chrome?.pids.count == 4)
        #expect(chrome?.footprint == 600 * MB + 3 * 500 * MB)
        #expect(state.groups.first?.displayName == "Python · FLUX.1-schnell")  // 11 GB is largest
    }

    @Test func suggestsChromeButNotFrontmostSafariOrPython() {
        let fake = makeWorld()
        let state = makeState(fake)
        state.setMenuOpen(true)
        #expect(state.candidates.map(\.name) == ["Google Chrome"])
        #expect(state.candidates.first?.pid == 100)
    }

    @Test func yellowPressureRunsTheFullPipelineEvenWithMenuClosed() {
        let fake = makeWorld()
        fake.pressure = .warning
        let state = makeState(fake)
        state.refresh()
        #expect(state.level == .warning)
        #expect(fake.listPidsCallCount == 1)
        #expect(!state.groups.isEmpty)
    }

    @Test func closingTheMenuReturnsToIconOnlyWhenGreen() {
        let fake = makeWorld()
        let state = makeState(fake)
        state.setMenuOpen(true)
        state.setMenuOpen(false)
        state.refresh()
        #expect(fake.listPidsCallCount == 1)   // only the refresh triggered by opening
    }

    @Test func criticalAlertFiresOncePerRedEpisodeAndRearmsOnGreen() {
        let fake = makeWorld()
        var alerts: [(String, String)] = []
        let state = makeState(fake, onAlert: { alerts.append(($0, $1)) })

        fake.pressure = .critical
        state.refresh()
        state.refresh()
        #expect(alerts.count == 1)
        #expect(alerts[0].0 == "Memory pressure is critical")
        #expect(alerts[0].1 == "Quit Google Chrome to free 2.1 GB.")

        fake.pressure = .warning
        state.refresh()
        fake.pressure = .critical
        state.refresh()
        #expect(alerts.count == 1)   // yellow does not re-arm

        fake.pressure = .normal
        state.refresh()
        fake.pressure = .critical
        state.refresh()
        #expect(alerts.count == 2)
    }

    @Test func disabledAlertsSendNothing() {
        let fake = makeWorld()
        var count = 0
        let state = makeState(fake, alertEnabled: { false }, onAlert: { _, _ in count += 1 })
        fake.pressure = .critical
        state.refresh()
        #expect(count == 0)
    }

    @Test func quitMarksWaitingForResponseWhenAppStaysRunning() async {
        let fake = makeWorld()
        let actions = FakeAppActions()
        actions.runningUntilCheck = nil
        let state = makeState(fake, actions: actions)
        state.setMenuOpen(true)
        let candidate = try! #require(state.candidates.first)

        await state.quit(candidate)

        #expect(actions.requested == [100])
        #expect(state.quitStatus[candidate.id] == .waitingForResponse)
    }

    @Test func quitClearsStatusAndRefreshesWhenAppExits() async {
        let fake = makeWorld()
        let actions = FakeAppActions()
        actions.runningUntilCheck = 0
        let state = makeState(fake, actions: actions)
        state.setMenuOpen(true)
        let candidate = try! #require(state.candidates.first)

        for pid in [100, 101, 102, 103] as [Int32] { fake.remove(pid: pid) }
        fake.apps = fake.apps.filter { $0.pid != 100 }
        await state.quit(candidate)

        #expect(state.quitStatus[candidate.id] == nil)
        #expect(state.candidates.isEmpty)
    }

    @Test func failedRequestIsReported() async {
        let fake = makeWorld()
        let actions = FakeAppActions()
        actions.acceptsRequest = false
        let state = makeState(fake, actions: actions)
        state.setMenuOpen(true)
        let candidate = try! #require(state.candidates.first)
        await state.quit(candidate)
        #expect(state.quitStatus[candidate.id] == .failed)
    }

    // MARK: - Lifecycle

    /// Records requested sleep durations. The first `freeRuns` sleeps return
    /// immediately; later ones park briefly (cancellable) so the loop idles.
    final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _durations: [Duration] = []
        let freeRuns: Int
        init(freeRuns: Int = 1) { self.freeRuns = freeRuns }
        var durations: [Duration] { lock.withLock { _durations } }
        func sleep(_ d: Duration) async {
            let n = lock.withLock { _durations.append(d); return _durations.count }
            if n > freeRuns { try? await Task.sleep(for: .milliseconds(100)) } else { await Task.yield() }
        }
    }

    func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2000 where !condition() { try? await Task.sleep(for: .milliseconds(2)) }
    }

    @Test func loopRefreshesAndRequestsThreeSecondsWhenGreen() async {
        let fake = makeWorld()
        let rec = SleepRecorder()
        let state = makeState(fake, sleep: { await rec.sleep($0) })
        state.setMenuOpen(true)          // one details pass so listPids is observable
        let base = fake.listPidsCallCount
        state.start()
        await waitUntil { !rec.durations.isEmpty }
        state.stop()
        #expect(rec.durations.first == .seconds(3))
        #expect(fake.listPidsCallCount > base)   // loop's refresh ran
    }

    @Test func loopRequestsOneSecondWhenWarningOrCritical() async {
        for level in [PressureLevel.warning, .critical] {
            let fake = makeWorld()
            fake.pressure = level
            let rec = SleepRecorder()
            let state = makeState(fake, sleep: { await rec.sleep($0) })
            state.start()
            await waitUntil { !rec.durations.isEmpty }
            state.stop()
            #expect(rec.durations.first == .seconds(1))
        }
    }

    @Test func noRefreshesAfterStop() async {
        let fake = makeWorld()
        fake.pressure = .warning
        let rec = SleepRecorder(freeRuns: .max)
        let state = makeState(fake, sleep: { await rec.sleep($0) })
        state.start()
        await waitUntil { rec.durations.count >= 2 }
        state.stop()
        try? await Task.sleep(for: .milliseconds(50))   // let any in-flight tick drain
        let frozen = fake.listPidsCallCount
        let frozenSleeps = rec.durations.count
        try? await Task.sleep(for: .milliseconds(100))
        #expect(fake.listPidsCallCount == frozen)
        #expect(rec.durations.count == frozenSleeps)
    }

    @Test func startingTwiceDoesNotRunTwoLoops() async {
        let fake = makeWorld()
        let rec = SleepRecorder(freeRuns: 0)   // every sleep parks 100 ms
        let state = makeState(fake, sleep: { await rec.sleep($0) })
        state.start()
        state.start()
        await waitUntil { !rec.durations.isEmpty }
        try? await Task.sleep(for: .milliseconds(30))
        state.stop()
        #expect(rec.durations.count == 1)   // a second live loop would have requested a second sleep
    }

    @Test func loopDoesNotKeepAppStateAlive() async {
        let fake = makeWorld()
        let rec = SleepRecorder(freeRuns: 0)
        var state: AppState? = makeState(fake, sleep: { await rec.sleep($0) })
        weak var weakState: AppState?
        weakState = state
        state?.start()
        await waitUntil { !rec.durations.isEmpty }
        state = nil
        #expect(weakState == nil)
    }

    @Test func secondQuitWhileRequestingIsIgnored() async {
        let fake = makeWorld()
        let actions = FakeAppActions()
        actions.runningUntilCheck = nil
        let state = AppState(
            reader: fake,
            terminator: AppTerminator(actions: actions, sleep: { _ in try? await Task.sleep(for: .milliseconds(20)) }),
            selfPid: 999)
        state.setMenuOpen(true)
        let candidate = try! #require(state.candidates.first)

        async let first: Void = state.quit(candidate)
        try? await Task.sleep(for: .milliseconds(5))
        await state.quit(candidate)    // re-entrant call while the first is in flight
        await first
        #expect(actions.requested == [100])
    }
}
