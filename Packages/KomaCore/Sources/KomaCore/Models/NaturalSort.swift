import Foundation

extension String {
    /// Natural ordering: numeric runs compare by value, case/width insensitive,
    /// and "/"-separated path components are compared one by one.
    public func naturalCompare(_ other: String) -> ComparisonResult {
        let lhs = self.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let rhs = other.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for (a, b) in zip(lhs, rhs) {
            let result = a.compare(b, options: [.numeric, .caseInsensitive, .widthInsensitive])
            if result != .orderedSame { return result }
        }
        if lhs.count == rhs.count { return .orderedSame }
        return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
    }
}

extension Array where Element == String {
    public func naturallySorted() -> [String] {
        sorted { $0.naturalCompare($1) == .orderedAscending }
    }
}
