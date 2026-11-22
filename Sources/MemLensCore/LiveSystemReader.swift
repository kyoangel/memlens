import AppKit
import Darwin
import Foundation

/// Production SystemReader backed by Darwin libproc / sysctl and NSWorkspace.
/// Needs no special privileges: processes owned by other users simply fail to
/// read and are skipped by callers.
public struct LiveSystemReader: SystemReader {
    public init() {}

    public func listPids() -> [Int32] {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard got > 0 else { return [] }
        return pids.prefix(Int(got)).filter { $0 > 0 }
    }

    public func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public func footprintBytes(pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    public func commandLine(pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 { index += 1 }  // skip exec path
        while index < size && buffer[index] == 0 { index += 1 }  // skip NUL padding
        var args: [String] = []
        while index < size && args.count < argc {
            var end = index
            while end < size && buffer[end] != 0 { end += 1 }
            args.append(String(decoding: buffer[index..<end], as: UTF8.self))
            index = end + 1
        }
        return args
    }

    public func filePaths(pid: Int32) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        func add(_ path: String) {
            if !path.isEmpty, seen.insert(path).inserted { paths.append(path) }
        }
        openFileDescriptorPaths(pid: pid, add: add)
        mappedFilePaths(pid: pid, add: add)
        return paths
    }

    public func pressureLevel() -> PressureLevel {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else {
            return .normal
        }
        return PressureLevel(sysctlValue: value)
    }

    public func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let path = app.bundleURL?.path else { return nil }
            let policy: AppActivationPolicy
            switch app.activationPolicy {
            case .regular: policy = .regular
            case .accessory: policy = .accessory
            default: policy = .prohibited
            }
            return RunningApp(
                pid: app.processIdentifier,
                bundlePath: path,
                name: app.localizedName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                policy: policy,
                isFrontmost: app.isActive
            )
        }
    }

    // MARK: - Private

    private func openFileDescriptorPaths(pid: Int32, add: (String) -> Void) {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return }
        let capacity = Int(bytes) / MemoryLayout<proc_fdinfo>.size + 8
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(capacity * MemoryLayout<proc_fdinfo>.size))
        guard got > 0 else { return }
        let count = Int(got) / MemoryLayout<proc_fdinfo>.size
        for fd in fds.prefix(count) where fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let r = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info,
                                   Int32(MemoryLayout<vnode_fdinfowithpath>.size))
            guard r >= Int32(MemoryLayout<vnode_fdinfowithpath>.size) else { continue }
            add(Self.string(fromPath: &info.pvip.vip_path))
        }
    }

    /// Libraries and model weights are usually memory-mapped (safetensors, GGUF)
    /// and the fd is closed right after, so scan the VM regions too.
    private func mappedFilePaths(pid: Int32, add: (String) -> Void) {
        var address: UInt64 = 0
        var info = proc_regionwithpathinfo()
        let size = Int32(MemoryLayout<proc_regionwithpathinfo>.size)
        var iterations = 0
        while iterations < 200_000 {
            iterations += 1
            guard proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &info, size) >= size else { return }
            add(Self.string(fromPath: &info.prp_vip.vip_path))
            let (next, overflow) = info.prp_prinfo.pri_address.addingReportingOverflow(info.prp_prinfo.pri_size)
            if overflow || next <= address { return }
            address = next
        }
    }

    /// `vip_path` is imported as a fixed-size tuple of CChar (MAXPATHLEN).
    private static func string<T>(fromPath tuple: inout T) -> String {
        withUnsafePointer(to: &tuple) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }
}
