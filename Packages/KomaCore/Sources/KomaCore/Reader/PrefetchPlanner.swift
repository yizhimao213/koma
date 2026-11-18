import Foundation

public struct PrefetchPlanner: Sendable {
    public var before: Int
    public var after: Int

    public init(before: Int = 2, after: Int = 5) {
        self.before = before
        self.after = after
    }

    /// Indices to prefetch around `current`, nearest first (forward before backward at equal distance), clamped to `0..<count`.
    public func indices(around current: Int, count: Int) -> [Int] {
        var result: [Int] = []
        let maxDistance = max(before, after, 0)
        guard maxDistance > 0 else { return result }
        for distance in 1...maxDistance {
            if distance <= after {
                let i = current + distance
                if i >= 0 && i < count { result.append(i) }
            }
            if distance <= before {
                let i = current - distance
                if i >= 0 && i < count { result.append(i) }
            }
        }
        return result
    }
}
