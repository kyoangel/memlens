import AppKit
import SwiftUI

/// Reports whether the MenuBarExtra window is currently shown, so AppState can
/// skip the expensive pipeline while the menu is closed and pressure is green.
struct MenuVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> TrackerView { TrackerView(onChange: onChange) }
    func updateNSView(_ nsView: TrackerView, context: Context) {}

    final class TrackerView: NSView {
        private let onChange: @MainActor (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onChange: @escaping @MainActor (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers = []
            guard let window else { return }

            func watch(_ name: Notification.Name, _ value: @escaping @MainActor (NSWindow) -> Bool) {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    guard let self, let window = note.object as? NSWindow else { return }
                    MainActor.assumeIsolated { self.onChange(value(window)) }
                })
            }
            watch(NSWindow.didBecomeKeyNotification) { _ in true }
            watch(NSWindow.didResignKeyNotification) { _ in false }
            watch(NSWindow.willCloseNotification) { _ in false }
            watch(NSWindow.didChangeOcclusionStateNotification) {
                $0.isVisible && $0.occlusionState.contains(.visible)
            }
            MainActor.assumeIsolated { onChange(window.isVisible && window.isKeyWindow) }
        }
    }
}
