import Foundation

/// Kernel memory-pressure level (`kern.memorystatus_vm_pressure_level`).
/// Raw values match the kernel: 1 = normal, 2 = warning, 4 = critical.
public enum PressureLevel: Int, Sendable, Comparable, CaseIterable {
    case normal = 1
    case warning = 2
    case critical = 4

    /// Unknown kernel values are treated as `.normal`.
    public init(sysctlValue: Int32) {
        switch sysctlValue {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }

    public static func < (lhs: PressureLevel, rhs: PressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum AppActivationPolicy: Sendable, Equatable {
    case regular    // Dock app
    case accessory  // menu bar / agent app (LSUIElement)
    case prohibited // background only
}

/// A GUI application as reported by NSWorkspace.
public struct RunningApp: Sendable, Equatable {
    public let pid: Int32
    public let bundlePath: String
    public let name: String
    public let policy: AppActivationPolicy
    public let isFrontmost: Bool

    public init(pid: Int32, bundlePath: String, name: String,
                policy: AppActivationPolicy, isFrontmost: Bool) {
        self.pid = pid
        self.bundlePath = bundlePath
        self.name = name
        self.policy = policy
        self.isFrontmost = isFrontmost
    }
}

/// The single seam for every OS read. Production: `LiveSystemReader`.
/// Tests: `FakeSystemReader`. Methods return nil / empty for anything
/// unreadable (permission, exited process); callers skip silently.
public protocol SystemReader: Sendable {
    func listPids() -> [Int32]
    func executablePath(pid: Int32) -> String?
    /// `ri_phys_footprint` in bytes: the metric behind Activity Monitor's Memory column.
    func footprintBytes(pid: Int32) -> UInt64?
    /// argv of the process (KERN_PROCARGS2).
    func commandLine(pid: Int32) -> [String]?
    /// Paths of files the process has open (fds) or memory-mapped, de-duplicated.
    func filePaths(pid: Int32) -> [String]
    func pressureLevel() -> PressureLevel
    func runningApps() -> [RunningApp]
}
