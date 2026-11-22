import AppKit
import SwiftUI

/// Row icon: the app's own icon when there is a bundle (like Activity Monitor),
/// otherwise an SF Symbol for the group kind.
struct GroupIcon: View {
    let bundlePath: String?
    let symbolName: String?

    private static let size: CGFloat = 16

    var body: some View {
        Group {
            if let bundlePath {
                Image(nsImage: AppIconCache.icon(for: bundlePath))
                    .resizable()
            } else {
                Image(systemName: symbolName ?? "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(1)
            }
        }
        .frame(width: Self.size, height: Self.size)
    }
}

/// `NSWorkspace.icon(forFile:)` hits the disk; the menu re-renders on every
/// refresh, so keep one image per bundle for the app's lifetime.
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for bundlePath: String) -> NSImage {
        if let cached = icons[bundlePath] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        icons[bundlePath] = icon
        return icon
    }
}
