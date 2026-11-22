import Foundation

public struct ReclaimCandidate: Sendable, Equatable, Identifiable {
    public let id: String          // ProcessGroup.id
    public let name: String
    public let pid: Int32          // the running app's main pid (what AppTerminator quits)
    public let footprint: UInt64   // bytes the whole app (all helpers) would free
    public let idleSeconds: TimeInterval?   // nil = unknown

    public init(id: String, name: String, pid: Int32, footprint: UInt64, idleSeconds: TimeInterval?) {
        self.id = id
        self.name = name
        self.pid = pid
        self.footprint = footprint
        self.idleSeconds = idleSeconds
    }
}

public struct ReclaimPolicy: Sendable, Equatable {
    /// Apps smaller than this are not worth suggesting.
    public var minFootprint: UInt64 = 500 << 20
    /// Apps used more recently than this (known idle only) are "in use".
    public var minKnownIdle: TimeInterval = 120
    /// Idle time stops adding weight after this many seconds.
    public var idleCap: TimeInterval = 4 * 3600
    public var limit = 5

    public init() {}
    public static let `default` = ReclaimPolicy()
}

public enum ReclaimAdvisor {
    /// Pure ranking. Score = footprint x (1 + idle hours, capped at 4).
    /// Unknown idle time scores with weight 1: ranked by size only and never
    /// treated as long-idle.
    ///
    /// Never suggested: non-Dock apps (menu bar/agent apps), apps under
    /// /System/, the frontmost app, MemLens itself, apps without a matching
    /// running GUI app, apps below `minFootprint`, and apps used within
    /// `minKnownIdle`.
    public static func advise(
        groups: [ProcessGroup],
        apps: [RunningApp],
        idleSeconds: (String) -> TimeInterval?,
        selfPid: Int32,
        policy: ReclaimPolicy = .default
    ) -> [ReclaimCandidate] {
        let appsByBundle = Dictionary(apps.map { ($0.bundlePath, $0) }, uniquingKeysWith: { first, _ in first })
        var scored: [(candidate: ReclaimCandidate, score: Double)] = []

        for group in groups where group.kind == .app {
            guard let bundle = group.bundlePath,
                  let app = appsByBundle[bundle],
                  app.policy == .regular,
                  !app.isFrontmost,
                  app.pid != selfPid,
                  !group.pids.contains(selfPid),
                  !bundle.hasPrefix("/System/"),
                  group.footprint >= policy.minFootprint else { continue }

            let idle = idleSeconds(bundle)
            if let idle, idle < policy.minKnownIdle { continue }

            let weight = idle.map { 1 + min($0, policy.idleCap) / 3600 } ?? 1
            let candidate = ReclaimCandidate(id: group.id, name: group.name, pid: app.pid,
                                             footprint: group.footprint, idleSeconds: idle)
            scored.append((candidate, Double(group.footprint) * weight))
        }

        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.candidate.footprint != $1.candidate.footprint { return $0.candidate.footprint > $1.candidate.footprint }
            return $0.candidate.id < $1.candidate.id
        }
        return scored.prefix(policy.limit).map(\.candidate)
    }
}
