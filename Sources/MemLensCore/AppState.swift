import Foundation
import Observation

public enum QuitStatus: Sendable, Equatable {
    case requesting
    case waitingForResponse   // app is still running 5 s after the quit request
    case failed
}

/// Observable store behind the menu bar UI. Owns the refresh loop.
///
/// Cost control: every refresh reads the pressure level (one sysctl, enough
/// for the icon). The expensive pipeline (sample -> group -> detect -> advise)
/// runs only while the menu is open or pressure is not green.
@MainActor
@Observable
public final class AppState {
    public private(set) var level: PressureLevel = .normal
    /// Largest groups first; capped to keep the observable payload small.
    public private(set) var groups: [ProcessGroup] = []
    public private(set) var candidates: [ReclaimCandidate] = []
    public private(set) var unreadableCount = 0
    public private(set) var quitStatus: [String: QuitStatus] = [:]
    public private(set) var menuOpen = false

    static let maxGroups = 30

    @ObservationIgnored private let reader: SystemReader
    @ObservationIgnored private let terminator: AppTerminator
    @ObservationIgnored private let activity: ActivityTracker
    @ObservationIgnored private let detector: ModelDetector
    @ObservationIgnored private let monitor: PressureMonitor
    @ObservationIgnored private let workspaceObserver: WorkspaceActivityObserver
    @ObservationIgnored private let selfPid: Int32
    @ObservationIgnored private let isAlertEnabled: @MainActor () -> Bool
    @ObservationIgnored private let sendAlert: @MainActor (_ title: String, _ body: String) -> Void
    @ObservationIgnored private var gate = RedEpisodeGate()
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(
        reader: SystemReader,
        terminator: AppTerminator,
        activity: ActivityTracker = ActivityTracker(),
        detector: ModelDetector? = nil,
        selfPid: Int32 = ProcessInfo.processInfo.processIdentifier,
        isAlertEnabled: @escaping @MainActor () -> Bool = { true },
        sendAlert: @escaping @MainActor (_ title: String, _ body: String) -> Void = { _, _ in },
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.reader = reader
        self.terminator = terminator
        self.activity = activity
        self.detector = detector ?? ModelDetector(reader: reader)
        self.monitor = PressureMonitor(reader: reader)
        self.workspaceObserver = WorkspaceActivityObserver(tracker: activity)
        self.selfPid = selfPid
        self.isAlertEnabled = isAlertEnabled
        self.sendAlert = sendAlert
        self.sleep = sleep
    }

    /// 3 s normally, 1 s while pressure is yellow or red.
    public static func refreshInterval(for level: PressureLevel) -> Duration {
        level == .normal ? .seconds(3) : .seconds(1)
    }

    // MARK: - Lifecycle

    public func start() {
        stop()
        activity.seed(from: reader.runningApps())
        workspaceObserver.start()
        monitor.start { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let sleep = self.sleep
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Hold self only for the synchronous tick, never across the sleep.
                guard let interval = self?.tick() else { return }
                await sleep(interval)
            }
        }
    }

    private func tick() -> Duration {
        refresh()
        return Self.refreshInterval(for: level)
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        monitor.stop()
        workspaceObserver.stop()
    }

    public func setMenuOpen(_ open: Bool) {
        menuOpen = open
        if open { refresh() }
    }

    // MARK: - Refresh

    /// One tick. Public so tests (and the menu opening) can drive it directly.
    public func refresh() {
        let newLevel = reader.pressureLevel()
        if newLevel != level { level = newLevel }

        if menuOpen || newLevel != .normal {
            refreshDetails()
        }

        if gate.shouldNotify(for: newLevel), isAlertEnabled() {
            let body = candidates.first.map { "Quit \($0.name) to free \(ByteFormat.string($0.footprint))." }
                ?? "Close some apps to free memory."
            sendAlert("Memory pressure is critical", body)
        }
    }

    private func refreshDetails() {
        let sample = ProcessSampler.sample(reader: reader)
        var grouped = Grouper.group(sample.processes)

        for index in grouped.indices where grouped[index].kind == .python {
            grouped[index].model = grouped[index].pids.lazy.compactMap { self.detector.detect(pid: $0) }.first
        }
        detector.prune(livePids: Set(sample.processes.map(\.pid)))

        let newCandidates = ReclaimAdvisor.advise(
            groups: grouped,
            apps: reader.runningApps(),
            idleSeconds: { self.activity.idleSeconds(bundlePath: $0) },
            selfPid: selfPid)

        groups = Array(grouped.prefix(Self.maxGroups))
        candidates = newCandidates
        unreadableCount = sample.unreadableCount
        let ids = Set(newCandidates.map(\.id))
        quitStatus = quitStatus.filter { ids.contains($0.key) }
    }

    // MARK: - Actions

    /// Graceful quit of a suggested app. Marks "waiting for response" if the
    /// app is still running 5 s later (e.g. it is showing a save dialog).
    public func quit(_ candidate: ReclaimCandidate) async {
        guard quitStatus[candidate.id] != .requesting else { return }
        quitStatus[candidate.id] = .requesting
        let result = await terminator.quit(pid: candidate.pid)
        // The candidate list may have been refreshed while we awaited.
        let stillListed = candidates.contains { $0.id == candidate.id }
        switch result {
        case .quit:
            quitStatus[candidate.id] = nil
            refresh()
        case .waitingForResponse:
            if stillListed { quitStatus[candidate.id] = .waitingForResponse }
        case .couldNotRequest:
            if stillListed { quitStatus[candidate.id] = .failed }
        }
    }
}
