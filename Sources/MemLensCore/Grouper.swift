import Foundation

public struct ProcessGroup: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case app      // merged under an outermost .app bundle
        case python   // one group per Python-like process, so each can show its own model
        case process  // non-bundled executable, merged by executable name
        case system   // pooled system daemons ("Other (system)")
    }

    public let id: String
    public let kind: Kind
    public var name: String
    public var bundlePath: String?
    public var pids: [Int32]
    public var footprint: UInt64
    /// Filled in by the caller after `ModelDetector` runs (Python groups only).
    public var model: String?

    public init(id: String, kind: Kind, name: String, bundlePath: String? = nil,
                pids: [Int32], footprint: UInt64, model: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.bundlePath = bundlePath
        self.pids = pids
        self.footprint = footprint
        self.model = model
    }

    /// "Python · FLUX.1-schnell" when a model was detected, else just the name.
    /// A model is never guessed: no detection means plain "Python".
    public var displayName: String {
        if kind == .python, let model { return "Python · \(model)" }
        return name
    }

    /// SF Symbol for groups without an app bundle; apps show their own icon (nil).
    public var symbolName: String? {
        switch kind {
        case .app: return nil
        case .process: return "terminal"
        case .python: return "cpu"
        case .system: return "gearshape"
        }
    }
}

public enum Grouper {
    static let systemPrefixes = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/", "/private/var/db/"]

    /// Merges helper processes into their parent app (outermost `.app` in the
    /// path, so `Chrome.app/.../Helper.app` lands in "Google Chrome"). Result is
    /// sorted by footprint, largest first.
    public static func group(_ processes: [RawProcess]) -> [ProcessGroup] {
        var groups: [String: ProcessGroup] = [:]

        func add(id: String, kind: ProcessGroup.Kind, name: String, bundlePath: String?, process: RawProcess) {
            if var existing = groups[id] {
                existing.pids.append(process.pid)
                existing.footprint += process.footprint
                groups[id] = existing
            } else {
                groups[id] = ProcessGroup(id: id, kind: kind, name: name, bundlePath: bundlePath,
                                          pids: [process.pid], footprint: process.footprint)
            }
        }

        for process in processes {
            if isPythonLike(process.executableName) {
                add(id: "pid:\(process.pid)", kind: .python, name: "Python", bundlePath: nil, process: process)
            } else if let bundle = outermostAppBundle(in: process.path) {
                let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
                add(id: bundle, kind: .app, name: name, bundlePath: bundle, process: process)
            } else if isSystemPath(process.path) {
                add(id: "system", kind: .system, name: "Other (system)", bundlePath: nil, process: process)
            } else {
                let name = processName(path: process.path, executableName: process.executableName)
                add(id: "proc:\(name)", kind: .process, name: productNames[name] ?? name,
                    bundlePath: nil, process: process)
            }
        }

        return groups.values.sorted {
            $0.footprint != $1.footprint ? $0.footprint > $1.footprint : $0.id < $1.id
        }
    }

    /// `/usr/local/` holds user-installed software (Homebrew on Intel, source builds),
    /// so it is excluded even though it sits under `/usr/`.
    static func isSystemPath(_ path: String) -> Bool {
        if path.hasPrefix("/usr/local/") { return false }
        return systemPrefixes.contains { path.hasPrefix($0) }
    }

    /// Version-managed installs (e.g. Claude Code at `~/.local/share/claude/versions/2.1.322`)
    /// resolve to an executable named only by its version. Walk up past version-like
    /// components and a "versions" directory to the tool's own directory name.
    /// Stops at generic directories (and home dirs) so unrelated binaries never
    /// get named, or merged, as "bin" or the user's name.
    static func processName(path: String, executableName: String) -> String {
        guard isVersionLike(executableName) else { return executableName }
        let components = path.split(separator: "/").dropLast()
        for index in components.indices.reversed() {
            let component = components[index]
            if isVersionLike(component) || component.lowercased() == "versions" { continue }
            let isHomeDir = index > components.startIndex
                && ["users", "home"].contains(components[index - 1].lowercased())
            if genericDirectories.contains(component.lowercased()) || isHomeDir { break }
            return String(component)
        }
        return executableName
    }

    /// Known CLI executables shown by product name, so e.g. the Claude Code CLI
    /// ("claude") is not confused with the Claude desktop app ("Claude").
    static let productNames: [String: String] = ["claude": "Claude Code"]

    static let genericDirectories: Set<String> = [
        "bin", "sbin", "lib", "libexec", "opt", "local", "share", ".local",
        "users", "home", "cellar", "homebrew", "applications",
    ]

    static func isVersionLike(_ name: some StringProtocol) -> Bool {
        String(name).wholeMatch(of: /v?\d+(\.\d+)+/) != nil
    }

    public static func isPythonLike(_ executableName: String) -> Bool {
        executableName.lowercased().hasPrefix("python")
    }

    /// "/A/B.app/Contents/Frameworks/H.app/Contents/MacOS/H" -> "/A/B.app"
    static func outermostAppBundle(in path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + components[...index].joined(separator: "/")
    }
}
