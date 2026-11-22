import Foundation
import Testing
@testable import MemLensCore

@MainActor
@Suite struct AppTerminatorTests {
    @Test func reportsQuitWhenAppExitsPromptly() async {
        let actions = FakeAppActions()
        actions.runningUntilCheck = 1
        let terminator = AppTerminator(actions: actions, sleep: { _ in })
        #expect(await terminator.quit(pid: 42) == .quit)
        #expect(actions.requested == [42])
    }

    @Test func reportsWaitingForResponseAfterFiveSeconds() async {
        let actions = FakeAppActions()
        actions.runningUntilCheck = nil   // e.g. blocked on a save dialog
        let slept = SleepLog()
        let terminator = AppTerminator(actions: actions, timeout: 5, pollInterval: 0.5,
                                       sleep: { await slept.record($0) })
        #expect(await terminator.quit(pid: 42) == .waitingForResponse)
        #expect(await slept.total == 5.0)
        #expect(actions.requested == [42])   // asked exactly once, never forced
    }

    @Test func exitJustBeforeTimeoutCountsAsQuit() async {
        let actions = FakeAppActions()
        actions.runningUntilCheck = 9   // gone on the 10th poll (t = 5.0 s)
        let terminator = AppTerminator(actions: actions, timeout: 5, pollInterval: 0.5, sleep: { _ in })
        #expect(await terminator.quit(pid: 1) == .quit)
    }

    @Test func runningUntilCheckTenStillWaitsForResponse() async {
        let actions = FakeAppActions()
        actions.runningUntilCheck = 10   // still running on the 10th poll
        let terminator = AppTerminator(actions: actions, timeout: 5, pollInterval: 0.5, sleep: { _ in })
        #expect(await terminator.quit(pid: 1) == .waitingForResponse)
    }

    @Test func cancellationStopsPollingInsteadOfSpinning() async {
        let actions = FakeAppActions()
        actions.runningUntilCheck = nil
        let terminator = AppTerminator(actions: actions, timeout: 5, pollInterval: 0.5, sleep: { _ in })
        let task = Task { await terminator.quit(pid: 1) }
        task.cancel()
        #expect(await task.value == .waitingForResponse)
        #expect(actions.checks <= 1)
    }

    @Test func cancellationReportsQuitIfAppAlreadyGone() async {
        let actions = FakeAppActions()
        actions.runningUntilCheck = 0
        let terminator = AppTerminator(actions: actions, timeout: 5, pollInterval: 0.5, sleep: { _ in })
        let task = Task { await terminator.quit(pid: 1) }
        task.cancel()
        #expect(await task.value == .quit)
    }

    @Test func nonPositivePollIntervalDoesNotTrap() async {
        let actions = FakeAppActions()
        actions.runningUntilCheck = nil
        let terminator = AppTerminator(actions: actions, timeout: 5, pollInterval: 0, sleep: { _ in })
        _ = await terminator.quit(pid: 1)
    }

    @Test func reportsCouldNotRequest() async {
        let actions = FakeAppActions()
        actions.acceptsRequest = false
        let terminator = AppTerminator(actions: actions, sleep: { _ in })
        #expect(await terminator.quit(pid: 1) == .couldNotRequest)
        #expect(actions.checks == 0)
    }

    @Test func liveActionsReportMissingPidAsNotRunning() {
        #expect(LiveAppActions().isRunning(pid: 0x7FFF_FFF0) == false)
        #expect(LiveAppActions().requestTerminate(pid: 0x7FFF_FFF0) == false)
    }
}

private actor SleepLog {
    private(set) var total: TimeInterval = 0
    func record(_ seconds: TimeInterval) { total += seconds }
}
