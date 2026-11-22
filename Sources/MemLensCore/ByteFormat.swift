import Foundation

public enum ByteFormat {
    /// Activity Monitor style (1024-based): "3.2 GB" from 1 GB up, else whole MB.
    public static func string(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / Double(1 << 30)
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / Double(1 << 20))
    }
}
