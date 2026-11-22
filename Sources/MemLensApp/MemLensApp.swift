import AppKit
import MemLensCore
import SwiftUI

@main
struct MemLensApp: App {
    private let state: AppState

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let state = AppState(
            reader: LiveSystemReader(),
            terminator: AppTerminator(actions: LiveAppActions()),
            isAlertEnabled: { UserDefaults.standard.object(forKey: "criticalNotifications") as? Bool ?? true },
            sendAlert: { CriticalNotifier.send(title: $0, body: $1) })
        CriticalNotifier.requestAuthorization()
        state.start()
        self.state = state
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(state: state)
        } label: {
            Image(nsImage: StatusIcon.image(for: state.level))
                .accessibilityLabel("MemLens, memory pressure \(StatusIcon.title(for: state.level))")
        }
        .menuBarExtraStyle(.window)
    }
}
