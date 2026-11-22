import Foundation

public struct RawProcess: Sendable, Equatable {
    public let pid: Int32
    public let path: String
    public let footprint: UInt64

    public init(pid: Int32, path: String, footprint: UInt64) {
        self.pid = pid
        self.path = path
        self.footprint = footprint
    }

    /// Last path component, e.g. "python3.12".
    public var executableName: String {
        (path as NSString).lastPathComponent
    }
}

public struct ProcessSample: Sendable, Equatable {
    public let processes: [RawProcess]
    /// Processes that could not be read (other users, exited mid-scan).
    public let unreadableCount: Int

    public init(processes: [RawProcess], unreadableCount: Int) {
        self.processes = processes
        self.unreadableCount = unreadableCount
    }
}

public enum ProcessSampler {
    /// Reads every pid once. Unreadable processes are skipped silently and
    /// only counted.
    public static func sample(reader: SystemReader) -> ProcessSample {
        var processes: [RawProcess] = []
        var unreadable = 0
        for pid in reader.listPids() {
            guard let path = reader.executablePath(pid: pid),
                  let footprint = reader.footprintBytes(pid: pid) else {
                unreadable += 1
                continue
            }
            processes.append(RawProcess(pid: pid, path: path, footprint: footprint))
        }
        return ProcessSample(processes: processes, unreadableCount: unreadable)
    }
}
