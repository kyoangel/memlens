import Foundation
@testable import MemLensCore

@MainActor
final class FakeAppActions: AppActions {
    var acceptsRequest = true
    var requested: [Int32] = []
    /// isRunning is true for this many checks, then false. nil = forever.
    var runningUntilCheck: Int? = 0
    private(set) var checks = 0

    func requestTerminate(pid: Int32) -> Bool {
        requested.append(pid)
        return acceptsRequest
    }

    func isRunning(pid: Int32) -> Bool {
        checks += 1
        guard let runningUntilCheck else { return true }
        return checks <= runningUntilCheck
    }
}
