/// Decides when to send the critical-pressure notification: once per red
/// episode, re-armed only after pressure returns to green (normal).
/// Yellow (warning) neither fires nor re-arms.
public struct RedEpisodeGate: Sendable, Equatable {
    private var armed = true

    public init() {}

    /// Feed every observed level; returns true exactly when a notification
    /// should be sent now.
    public mutating func shouldNotify(for level: PressureLevel) -> Bool {
        switch level {
        case .critical:
            guard armed else { return false }
            armed = false
            return true
        case .normal:
            armed = true
            return false
        case .warning:
            return false
        }
    }
}
