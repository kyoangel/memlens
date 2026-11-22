import Dispatch
import Foundation

/// Current memory-pressure level plus change events from the kernel.
/// The kernel event only wakes us; the level is always re-read through the
/// SystemReader so there is one source of truth.
public final class PressureMonitor: @unchecked Sendable {
    private let reader: SystemReader
    private let lock = NSLock()
    private var source: DispatchSourceMemoryPressure?

    public init(reader: SystemReader) {
        self.reader = reader
    }

    public var current: PressureLevel { reader.pressureLevel() }

    /// Calls `onChange` on the main queue whenever the kernel reports a
    /// pressure transition. Calling `start` again replaces the previous handler.
    public func start(onChange: @escaping @Sendable (PressureLevel) -> Void) {
        stop()
        let newSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main)
        let reader = self.reader
        newSource.setEventHandler { onChange(reader.pressureLevel()) }
        lock.withLock { source = newSource }
        newSource.resume()
    }

    public func stop() {
        let old = lock.withLock { () -> DispatchSourceMemoryPressure? in
            defer { source = nil }
            return source
        }
        old?.cancel()
    }

    deinit { stop() }
}
