import AppKit
import MemLensCore
import SwiftUI

struct MenuContentView: View {
    let state: AppState
    @AppStorage("criticalNotifications") private var criticalNotifications = true

    private static let visibleGroups = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !state.candidates.isEmpty { suggestions }
            memoryList
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .background(MenuVisibilityReader { state.setMenuOpen($0) })
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: StatusIcon.image(for: state.level))
                .accessibilityHidden(true)
            Text("Memory pressure: \(StatusIcon.title(for: state.level))")
                .font(.headline)
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.level == .normal ? "Could free" : "Quit to free memory")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(state.candidates) { candidate in
                HStack(spacing: 6) {
                    // Candidates are always app groups, whose id is the bundle path.
                    GroupIcon(bundlePath: candidate.id, symbolName: nil)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Quit \(candidate.name) to free \(ByteFormat.string(candidate.footprint))")
                            .lineLimit(1)
                        if let note = note(for: candidate) {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Quit") { Task { await state.quit(candidate) } }
                        .disabled(state.quitStatus[candidate.id] == .requesting)
                }
            }
        }
    }

    private func note(for candidate: ReclaimCandidate) -> String? {
        switch state.quitStatus[candidate.id] {
        case .requesting: return "Quitting..."
        case .waitingForResponse: return "Waiting for response (the app may be asking to save)"
        case .failed: return "Could not send the quit request"
        case nil:
            guard let idle = candidate.idleSeconds else { return nil }
            return "Idle \(Self.idleText(idle))"
        }
    }

    private static func idleText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    private var memoryList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Memory by app").font(.subheadline).foregroundStyle(.secondary)
            ForEach(state.groups.prefix(Self.visibleGroups)) { group in
                HStack(spacing: 6) {
                    GroupIcon(bundlePath: group.bundlePath, symbolName: group.symbolName)
                    Text(group.displayName).lineLimit(1)
                    Spacer()
                    Text(ByteFormat.string(group.footprint)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if state.unreadableCount > 0 {
                Text("\(state.unreadableCount) other processes not readable")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Notify when pressure is critical", isOn: $criticalNotifications)
            Button("Quit MemLens") { NSApplication.shared.terminate(nil) }
        }
    }
}
