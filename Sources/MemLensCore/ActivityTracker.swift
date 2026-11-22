import AppKit
import Foundation

/// Last-foreground time per app bundle. Only apps observed while MemLens
/// runs are known; everything else reports nil ("unknown"), which
/// `ReclaimAdvisor` must never treat as long-idle.
public final class ActivityTracker: @unchecked Sendable {
    private enum State {
        case frontmost
        case inactive(since: Date)
    }

    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var states: [String: State] = [:]

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// The app became frontmost; it stays at 0 idle until it is deactivated.
    public func recordActivation(bundlePath: String) {
        lock.withLock { states[bundlePath] = .frontmost }
    }

    /// The app stopped being frontmost; idle time counts from now.
    public func recordDeactivation(bundlePath: String) {
        let time = now()
        lock.withLock { states[bundlePath] = .inactive(since: time) }
    }

    /// Record the app that is frontmost right now (called once at launch).
    public func seed(from apps: [RunningApp]) {
        for app in apps where app.isFrontmost { recordActivation(bundlePath: app.bundlePath) }
    }

    /// Seconds since the app stopped being frontmost; 0 while it is frontmost;
    /// nil if never observed.
    public func idleSeconds(bundlePath: String) -> TimeInterval? {
        let current = now()
        guard let state = lock.withLock({ states[bundlePath] }) else { return nil }
        switch state {
        case .frontmost: return 0
        case .inactive(let since): return max(0, current.timeIntervalSince(since))
        }
    }
}

/// Feeds NSWorkspace activate/deactivate notifications into an ActivityTracker.
public final class WorkspaceActivityObserver: @unchecked Sendable {
    private let tracker: ActivityTracker
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []

    public init(tracker: ActivityTracker) {
        self.tracker = tracker
    }

    func handle(_ name: Notification.Name, app: NSRunningApplication?) {
        handle(name, bundlePath: app?.bundleURL?.path)
    }

    func handle(_ name: Notification.Name, bundlePath path: String?) {
        guard let path else { return }
        switch name {
        case NSWorkspace.didActivateApplicationNotification:
            tracker.recordActivation(bundlePath: path)
        case NSWorkspace.didDeactivateApplicationNotification:
            tracker.recordDeactivation(bundlePath: path)
        default:
            break
        }
    }

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        let newTokens = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.handle(notification.name, app: app)
            }
        }
        let old = lock.withLock { () -> [NSObjectProtocol] in
            defer { tokens = newTokens }
            return tokens
        }
        old.forEach { center.removeObserver($0) }
    }

    public func stop() {
        let old = lock.withLock { () -> [NSObjectProtocol] in
            defer { tokens = [] }
            return tokens
        }
        old.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    deinit { stop() }
}
