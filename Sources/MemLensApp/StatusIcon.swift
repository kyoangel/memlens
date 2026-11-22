import AppKit
import MemLensCore

enum StatusIcon {
    /// Memory chip + colored lens (see StatusIconRenderer). Deliberately NOT a
    /// template image, otherwise the lens color would be lost.
    static func image(for level: PressureLevel) -> NSImage {
        StatusIconRenderer.image(for: level)
    }

    static func title(for level: PressureLevel) -> String {
        switch level {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}
