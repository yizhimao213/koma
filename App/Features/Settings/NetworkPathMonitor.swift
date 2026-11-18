import Foundation
import Network

/// Watches the current network path and publishes whether it is expensive (e.g. cellular).
final class NetworkPathMonitor: ObservableObject {
    @Published private(set) var isExpensive: Bool = false

    private static let lock = NSLock()
    private static var expensiveFlag = false

    /// Thread-safe latest value, readable from any queue.
    static var isExpensiveSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return expensiveFlag
    }

    private static func setSnapshot(_ value: Bool) {
        lock.lock()
        expensiveFlag = value
        lock.unlock()
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "koma.network-path-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive
            NetworkPathMonitor.setSnapshot(expensive)
            DispatchQueue.main.async {
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
