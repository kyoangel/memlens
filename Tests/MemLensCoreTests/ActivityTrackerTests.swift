import AppKit
import Foundation
import Testing
@testable import MemLensCore

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 2_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@Suite struct ActivityTrackerTests {
    @Test func unknownAppHasNoIdleTime() {
        let tracker = ActivityTracker()
        #expect(tracker.idleSeconds(bundlePath: "/Applications/Foo.app") == nil)
    }

    @Test func idleTimeGrowsSinceDeactivation() {
        let clock = TestClock()
        let tracker = ActivityTracker(now: { clock.now })
        tracker.recordActivation(bundlePath: "/Applications/Foo.app")
        tracker.recordDeactivation(bundlePath: "/Applications/Foo.app")
        clock.advance(600)
        #expect(tracker.idleSeconds(bundlePath: "/Applications/Foo.app") == 600)
    }

    @Test func reactivationResetsIdleTime() {
        let clock = TestClock()
        let tracker = ActivityTracker(now: { clock.now })
        tracker.recordDeactivation(bundlePath: "/Applications/Foo.app")
        clock.advance(600)
        tracker.recordActivation(bundlePath: "/Applications/Foo.app")
        #expect(tracker.idleSeconds(bundlePath: "/Applications/Foo.app") == 0)
        tracker.recordDeactivation(bundlePath: "/Applications/Foo.app")
        clock.advance(30)
        #expect(tracker.idleSeconds(bundlePath: "/Applications/Foo.app") == 30)
    }

    @Test func seedRecordsOnlyTheFrontmostApp() {
        let clock = TestClock()
        let tracker = ActivityTracker(now: { clock.now })
        tracker.seed(from: [
            RunningApp(pid: 1, bundlePath: "/Applications/Front.app", name: "Front", policy: .regular, isFrontmost: true),
            RunningApp(pid: 2, bundlePath: "/Applications/Back.app", name: "Back", policy: .regular, isFrontmost: false),
        ])
        clock.advance(5)
        #expect(tracker.idleSeconds(bundlePath: "/Applications/Front.app") == 0)
        tracker.recordDeactivation(bundlePath: "/Applications/Front.app")
        clock.advance(5)
        #expect(tracker.idleSeconds(bundlePath: "/Applications/Front.app") == 5)
        #expect(tracker.idleSeconds(bundlePath: "/Applications/Back.app") == nil)
    }

    @Test func idleTimeStartsWhenAppLosesFocus() {
        let clock = TestClock()
        let tracker = ActivityTracker(now: { clock.now })
        let path = "/Applications/Foo.app"
        tracker.recordActivation(bundlePath: path)
        clock.advance(7200)
        #expect(tracker.idleSeconds(bundlePath: path) == 0)
        tracker.recordDeactivation(bundlePath: path)
        clock.advance(600)
        #expect(tracker.idleSeconds(bundlePath: path) == 600)
    }

    @Test func deactivationOfUnobservedAppStartsIdleClock() {
        let clock = TestClock()
        let tracker = ActivityTracker(now: { clock.now })
        tracker.recordDeactivation(bundlePath: "/Applications/Foo.app")
        clock.advance(10)
        #expect(tracker.idleSeconds(bundlePath: "/Applications/Foo.app") == 10)
    }

    @Test func observerHandlesActivationAndDeactivation() {
        let clock = TestClock()
        let tracker = ActivityTracker(now: { clock.now })
        let observer = WorkspaceActivityObserver(tracker: tracker)
        let path = "/Applications/Foo.app"
        observer.handle(NSWorkspace.didActivateApplicationNotification, bundlePath: path)
        clock.advance(3600)
        #expect(tracker.idleSeconds(bundlePath: path) == 0)
        observer.handle(NSWorkspace.didDeactivateApplicationNotification, bundlePath: path)
        clock.advance(120)
        #expect(tracker.idleSeconds(bundlePath: path) == 120)
    }

    @Test func observerIgnoresNilAppAndUnrelatedNotifications() {
        let tracker = ActivityTracker()
        let observer = WorkspaceActivityObserver(tracker: tracker)
        let path = "/Applications/Foo.app"
        observer.handle(NSWorkspace.didActivateApplicationNotification, app: nil)
        observer.handle(NSWorkspace.didDeactivateApplicationNotification, bundlePath: nil)
        observer.handle(Notification.Name("unrelated"), bundlePath: path)
        #expect(tracker.idleSeconds(bundlePath: path) == nil)
    }

    @Test func workspaceObserverStartsAndStops() {
        let observer = WorkspaceActivityObserver(tracker: ActivityTracker())
        observer.start()
        observer.start()
        observer.stop()
        observer.stop()
    }
}
