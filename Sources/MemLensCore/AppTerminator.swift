import AppKit
import Foundation

public enum QuitOutcome: Sendable, Equatable {
    case quit                // app exited within the timeout
    case waitingForResponse  // still running after the timeout (e.g. a save dialog)
    case couldNotRequest     // the OS refused to deliver the quit request
}

/// The only write path to other processes. Graceful quit only: never force-kill.
@MainActor
public protocol AppActions {
    /// Sends the quit request (like Cmd-Q). Returns false if it could not be sent.
    func requestTerminate(pid: Int32) -> Bool
    func isRunning(pid: Int32) -> Bool
}

@MainActor
public struct LiveAppActions: AppActions {
    public init() {}

    public func requestTerminate(pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
    }

    public func isRunning(pid: Int32) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return !app.isTerminated
    }
}

@MainActor
public final class AppTerminator {
    private let actions: AppActions
    private let pollCount: Int
    private let pollInterval: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void

    /// After the request, polls every `pollInterval` seconds until `timeout`.
    /// The app is never touched again after the first request.
    public init(
        actions: AppActions,
        timeout: TimeInterval = 5,
        pollInterval: TimeInterval = 0.5,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.actions = actions
        let interval = max(pollInterval, 0.001)   // guard against zero/negative/NaN intervals
        let polls = (timeout / interval).rounded()
        self.pollInterval = interval
        self.pollCount = polls.isFinite ? max(1, Int(min(polls, 100_000))) : 1
        self.sleep = sleep
    }

    public func quit(pid: Int32) async -> QuitOutcome {
        guard actions.requestTerminate(pid: pid) else { return .couldNotRequest }
        for _ in 0..<pollCount {
            await sleep(pollInterval)
            if !actions.isRunning(pid: pid) { return .quit }
            // A cancelled Task makes Task.sleep return instantly; don't burn through the
            // remaining polls and report a false timeout.
            if Task.isCancelled { return .waitingForResponse }
        }
        return .waitingForResponse
    }
}
