import Foundation

/// Cache key strings for `BrowseCache`. List keys include the 18+ state so that turning 18+ off
/// never surfaces a page that was cached while it was on.
public enum BrowseCacheKey {
    public static let featured = "featured"
    public static let adult = "adult"

    /// e.g. `list("popular", adult: true) == "popular.adult1"`.
    public static func list(_ kind: String, adult: Bool) -> String {
        "\(kind).adult\(adult ? 1 : 0)"
    }
}

/// Pure pagination bookkeeping for infinite-scroll lists.
public struct PaginationState: Sendable {
    public private(set) var items: [MangaRef]
    public private(set) var loadedPage: Int
    public private(set) var hasNextPage: Bool
    public private(set) var isLoading: Bool
    /// How many trailing items trigger loading the next page when they appear.
    public let prefetchThreshold: Int

    public init(prefetchThreshold: Int = 6) {
        self.items = []
        self.loadedPage = 0
        self.hasNextPage = true
        self.isLoading = false
        self.prefetchThreshold = prefetchThreshold
    }

    public var isEmpty: Bool { items.isEmpty }

    /// True when the item at `index` is among the last `prefetchThreshold` items and another page can be loaded.
    public func shouldLoadMore(appearingIndex index: Int) -> Bool {
        guard hasNextPage, !isLoading, !items.isEmpty else { return false }
        return index >= items.count - prefetchThreshold
    }

    /// Marks a load as started and returns the page to request, or nil if a load is already
    /// running or there are no more pages.
    public mutating func beginNextPage() -> Int? {
        guard !isLoading, hasNextPage else { return nil }
        isLoading = true
        return loadedPage + 1
    }

    /// Starts reloading page 1 while keeping the current items visible until it arrives
    /// (pull-to-refresh). Callers cancel any in-flight load first.
    public mutating func beginRefresh() -> Int {
        isLoading = true
        return 1
    }

    /// Shows cached items while page 1 has not been loaded yet. Pagination still starts at page 1.
    public mutating func seed(with page: MangaPage) {
        guard loadedPage == 0, items.isEmpty else { return }
        items = page.items
    }

    /// Applies a fetched page. Items already present (same source and id) are dropped so
    /// shifting server-side lists never produce duplicate identities.
    public mutating func finish(page number: Int, with page: MangaPage) {
        isLoading = false
        if number == 1 {
            items = []
        }
        var seen = Set(items.map { Self.key($0) })
        for item in page.items where seen.insert(Self.key(item)).inserted {
            items.append(item)
        }
        loadedPage = number
        hasNextPage = page.hasNextPage && !page.items.isEmpty
    }

    /// Marks the running load as failed; the same page can be retried with `beginNextPage()`.
    public mutating func fail() {
        isLoading = false
    }

    private static func key(_ ref: MangaRef) -> String { "\(ref.sourceId)/\(ref.id)" }
}

/// Turns an average cover color into a deep background tone.
public enum CoverTone {
    public static let maxSaturation = 0.6
    public static let maxBrightness = 0.25

    /// Clamps saturation and brightness (HSB, 0...1) so light text stays readable on top.
    public static func deepened(hue: Double, saturation: Double, brightness: Double)
        -> (hue: Double, saturation: Double, brightness: Double) {
        let h = hue.isFinite ? min(max(hue, 0), 1) : 0
        let s = saturation.isFinite ? min(max(saturation, 0), maxSaturation) : 0
        let b = brightness.isFinite ? min(max(brightness, 0), maxBrightness) : 0
        return (h, s, b)
    }
}
