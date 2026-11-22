import Foundation

/// Rule-based detection of which model (or at least which AI runtime) a
/// Python-like process runs. Callers only invoke it for Python groups.
///
/// Rules, in priority order (adding a runtime means adding a rule):
/// 1. An open or memory-mapped file inside the Hugging Face cache
///    (`.../models--org--Name/{blobs,snapshots,refs}/...`) gives the model name.
/// 2. A model flag on the command line (`--model org/Name`) gives the model name.
/// 3. A runtime keyword in the command line (ComfyUI, mlx, llama, diffusers,
///    torch) gives a runtime label instead. A name is never guessed.
///
/// Results are cached per pid: a model-name hit is kept until `prune`; a miss or
/// a runtime-label fallback is rechecked after `negativeRecheckInterval` because
/// the model may still be loading.
public final class ModelDetector: @unchecked Sendable {
    private struct Entry {
        let result: String?
        /// True when `result` is a runtime-label fallback rather than a model name.
        let isRuntimeLabel: Bool
        let checkedAt: Date
    }

    private let reader: SystemReader
    private let negativeRecheckInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var cache: [Int32: Entry] = [:]

    public init(reader: SystemReader,
                negativeRecheckInterval: TimeInterval = 10,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.reader = reader
        self.negativeRecheckInterval = negativeRecheckInterval
        self.now = now
    }

    public func detect(pid: Int32) -> String? {
        let current = now()
        let cached = lock.withLock { cache[pid] }
        if let cached {
            if cached.result != nil, !cached.isRuntimeLabel { return cached.result }
            if current.timeIntervalSince(cached.checkedAt) < negativeRecheckInterval { return cached.result }
        }
        let (result, isLabel) = Self.classify(pid: pid, reader: reader)
        lock.withLock { cache[pid] = Entry(result: result, isRuntimeLabel: isLabel, checkedAt: current) }
        return result
    }

    /// Drop cache entries for processes that are gone.
    public func prune(livePids: Set<Int32>) {
        lock.withLock { cache = cache.filter { livePids.contains($0.key) } }
    }

    // MARK: - Rules (internal for tests)

    static func detectUncached(pid: Int32, reader: SystemReader) -> String? {
        classify(pid: pid, reader: reader).result
    }

    static func classify(pid: Int32, reader: SystemReader) -> (result: String?, isRuntimeLabel: Bool) {
        for path in reader.filePaths(pid: pid) {
            if let name = modelName(fromHFCachePath: path) { return (name, false) }
        }
        guard let args = reader.commandLine(pid: pid) else { return (nil, false) }
        if let name = modelName(fromArguments: args) { return (name, false) }
        if let label = runtimeLabel(fromArguments: args) { return (label, true) }
        return (nil, false)
    }

    /// ".../hub/models--black-forest-labs--FLUX.1-schnell/snapshots/abc/x.safetensors" -> "FLUX.1-schnell"
    static func modelName(fromHFCachePath path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.contains(where: { ["blobs", "snapshots", "refs"].contains($0) }),
              let repoDir = components.first(where: { $0.hasPrefix("models--") }) else { return nil }
        let repo = String(repoDir.dropFirst("models--".count))
        let name: String
        if let separator = repo.range(of: "--") {
            name = String(repo[separator.upperBound...])
        } else {
            name = repo
        }
        return name.isEmpty ? nil : name
    }

    /// `--model black-forest-labs/FLUX.1-schnell` or `--model=black-forest-labs/FLUX.1-schnell` -> "FLUX.1-schnell"
    static func modelName(fromArguments args: [String]) -> String? {
        if let name = mfluxModelName(fromArguments: args) { return name }
        let flags = ["--model", "--model-id", "--model_id", "--model_name_or_path", "--repo-id"]
        for (index, arg) in args.enumerated() {
            var value: String?
            if flags.contains(arg), index + 1 < args.count {
                value = args[index + 1]
            } else if let flag = flags.first(where: { arg.hasPrefix($0 + "=") }) {
                value = String(arg.dropFirst(flag.count + 1))
            }
            guard let value, isRepoID(value) else { continue }
            return String(value.split(separator: "/").last ?? "")
        }
        return nil
    }

    /// mflux (`mflux-generate --model schnell`) loads weights, quantizes and closes
    /// the files, so after the first seconds only its arguments name the model.
    /// FLUX aliases expand to the repo name; other aliases are shown as given.
    static func mfluxModelName(fromArguments args: [String]) -> String? {
        // The executable is args[0] (direct) or args[1] (interpreter + script);
        // later args are data and must not make a process look like mflux.
        let isMflux = args.prefix(2).contains { ($0 as NSString).lastPathComponent.lowercased().hasPrefix("mflux") }
        guard isMflux else { return nil }
        for (index, arg) in args.enumerated() {
            var value: String?
            if arg == "--model" || arg == "-m", index + 1 < args.count {
                value = args[index + 1]
            } else if arg.hasPrefix("--model=") {
                value = String(arg.dropFirst("--model=".count))
            }
            guard let value, !value.isEmpty, !value.hasPrefix("-") else { continue }
            // Known limit (shared with mflux itself): a relative "dir/ckpt" is
            // indistinguishable from an "org/name" repo id and reads as one.
            if isRepoID(value) { return String(value.split(separator: "/").last ?? "") }
            if value.contains("/") || value.hasPrefix(".") || value.hasPrefix("~") { return nil }  // local path
            return mfluxFluxAliases[value.lowercased()] ?? value
        }
        return nil
    }

    static let mfluxFluxAliases: [String: String] = [
        "schnell": "FLUX.1-schnell",
        "dev": "FLUX.1-dev",
        "krea-dev": "FLUX.1-Krea-dev",
        "dev-krea": "FLUX.1-Krea-dev",
        "dev-kontext": "FLUX.1-Kontext-dev",
    ]

    static func runtimeLabel(fromArguments args: [String]) -> String? {
        let joined = args.joined(separator: " ").lowercased()
        let rules: [(keyword: String, label: String)] = [
            ("comfyui", "ComfyUI"),
            ("mflux", "mflux"),
            ("mlx", "MLX"),
            ("llama", "llama"),
            ("diffusers", "diffusers"),
            ("torch", "PyTorch"),
        ]
        return rules.first { joined.contains($0.keyword) }?.label
    }

    private static func isRepoID(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !value.hasPrefix(".") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return parts.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }
    }
}
