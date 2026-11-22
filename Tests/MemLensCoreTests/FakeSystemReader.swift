import Foundation
@testable import MemLensCore

/// In-memory SystemReader for unit tests. Build a world with `add(...)`.
final class FakeSystemReader: SystemReader, @unchecked Sendable {
    struct Proc {
        var path: String?
        var footprint: UInt64?
        var args: [String]?
        var files: [String]
    }

    private let lock = NSLock()
    private var procs: [Int32: Proc] = [:]
    private var _pressure: PressureLevel = .normal
    private var _apps: [RunningApp] = []
    private var _filePathCalls: [Int32: Int] = [:]
    private var _listCalls = 0

    var pressure: PressureLevel {
        get { lock.withLock { _pressure } }
        set { lock.withLock { _pressure = newValue } }
    }
    var apps: [RunningApp] {
        get { lock.withLock { _apps } }
        set { lock.withLock { _apps = newValue } }
    }
    var listPidsCallCount: Int { lock.withLock { _listCalls } }
    func filePathsCallCount(pid: Int32) -> Int { lock.withLock { _filePathCalls[pid] ?? 0 } }

    func add(pid: Int32, path: String?, footprint: UInt64?,
             args: [String]? = nil, files: [String] = []) {
        lock.withLock { procs[pid] = Proc(path: path, footprint: footprint, args: args, files: files) }
    }
    func setFiles(pid: Int32, _ files: [String]) {
        lock.withLock { procs[pid]?.files = files }
    }
    func remove(pid: Int32) { lock.withLock { _ = procs.removeValue(forKey: pid) } }

    func listPids() -> [Int32] {
        lock.withLock { _listCalls += 1; return procs.keys.sorted() }
    }
    func executablePath(pid: Int32) -> String? { lock.withLock { procs[pid]?.path } }
    func footprintBytes(pid: Int32) -> UInt64? { lock.withLock { procs[pid]?.footprint } }
    func commandLine(pid: Int32) -> [String]? { lock.withLock { procs[pid]?.args } }
    func filePaths(pid: Int32) -> [String] {
        lock.withLock { _filePathCalls[pid, default: 0] += 1; return procs[pid]?.files ?? [] }
    }
    func pressureLevel() -> PressureLevel { pressure }
    func runningApps() -> [RunningApp] { apps }
}

let MB: UInt64 = 1 << 20
let GB: UInt64 = 1 << 30
