import SwiftUI
import KomaCore

/// Navigation destinations inside the Discover tab's NavigationStack.
enum DiscoverRoute: Hashable {
    case manga(MangaRef)
    case sourceList(sourceId: String, kind: SourceListKind)
    case search
}

/// User-facing (Simplified Chinese) messages for browse/search failures.
enum BrowseErrorText {
    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "网络未连接，请检查网络后重试"
            case .timedOut:
                return "连接超时，可以在「设置 → 网络」更换镜像或开启代理"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed:
                return "无法连接服务器，可以在「设置 → 网络」更换镜像或开启代理"
            default:
                return "网络异常，请稍后重试"
            }
        }
        if let httpError = error as? HTTPError {
            if httpError.statusCode == 429 { return "请求太频繁，请稍后再试" }
            return "服务器暂时不可用（\(httpError.statusCode)）"
        }
        if let sourceError = error as? SourceError {
            switch sourceError {
            case .unsupported: return "这个漫画源不支持该功能"
            case .notFound: return "没有找到内容"
            case .network: return "网络异常，请稍后重试"
            case .parse: return "数据解析失败，请稍后重试"
            }
        }
        return "加载失败，请稍后重试"
    }
}

enum RowState: Equatable {
    case loading
    case loaded
    case failed(String)
}

struct DiscoverRow: Equatable {
    var items: [MangaRef] = []
    var state: RowState = .loading

    /// Showing cached items because the latest refresh failed.
    var isStale: Bool {
        if case .failed = state { return !items.isEmpty }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }
}

enum DiscoverRowKind: CaseIterable {
    case featured, popular, latest, adult

    func cacheKey(adult: Bool) -> String {
        switch self {
        case .featured: return BrowseCacheKey.featured
        case .popular: return BrowseCacheKey.list("popular", adult: adult)
        case .latest: return BrowseCacheKey.list("latest", adult: adult)
        case .adult: return BrowseCacheKey.adult
        }
    }
}

/// Discover rows: each loads from `BrowseCache` first, then the network, storing the result back.
@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published private(set) var featured = DiscoverRow()
    @Published private(set) var popular = DiscoverRow()
    @Published private(set) var latest = DiscoverRow()
    @Published private(set) var adult = DiscoverRow()
    @Published private(set) var adultEnabled = false
    /// Lazily fetched details (tags, status) for hero slides, keyed by manga id.
    @Published private(set) var heroDetails: [String: MangaDetails] = [:]

    let mangaDex: MangaDexSource?
    private let cache: BrowseCache
    private var loadTask: Task<Void, Never>?
    private var heroDetailRequests = Set<String>()
    private var started = false

    init(sources: SourceRegistry, cache: BrowseCache) {
        mangaDex = sources.source(id: "mangadex") as? MangaDexSource
        self.cache = cache
    }

    var hasMangaDex: Bool { mangaDex != nil }

    /// Rows currently shown (the adult row only when 18+ is enabled).
    private var visibleKinds: [DiscoverRowKind] {
        adultEnabled ? DiscoverRowKind.allCases : [.featured, .popular, .latest]
    }

    /// True when every visible row failed with nothing cached to show.
    var allFailedEmpty: Bool {
        guard hasMangaDex else { return false }
        return visibleKinds.allSatisfy { kind in
            let row = self.row(kind)
            return row.items.isEmpty && row.failureMessage != nil
        }
    }

    /// True when any visible row is showing cached items after a failed refresh.
    var hasStaleRows: Bool {
        visibleKinds.contains { row($0).isStale }
    }

    func loadIfNeeded(showAdult: Bool) {
        guard !started else { return }
        started = true
        adultEnabled = showAdult
        startLoading()
    }

    /// Called when the 18+ preference changes: drops rows from the other rating set and reloads.
    func adultChanged(_ showAdult: Bool) {
        guard showAdult != adultEnabled else { return }
        adultEnabled = showAdult
        popular = DiscoverRow()
        latest = DiscoverRow()
        adult = DiscoverRow()
        guard started else { return }
        startLoading()
    }

    /// Reloads every visible row (cache first, then network).
    func retryAll() {
        startLoading()
    }

    /// Pull-to-refresh: reloads and waits for completion.
    func refresh() async {
        startLoading()
        await loadTask?.value
    }

    func retry(_ kind: DiscoverRowKind) {
        guard let source = mangaDex else { return }
        let adultFlag = adultEnabled
        Task { await loadRow(kind, source: source, adult: adultFlag) }
    }

    /// Fetches details for a hero slide once, to show its tags and status.
    func loadHeroDetails(for ref: MangaRef) {
        guard let source = mangaDex, heroDetails[ref.id] == nil, !heroDetailRequests.contains(ref.id) else { return }
        heroDetailRequests.insert(ref.id)
        Task {
            if let details = try? await source.details(for: ref) {
                heroDetails[ref.id] = details
            } else {
                heroDetailRequests.remove(ref.id)
            }
        }
    }

    // MARK: - Loading

    private func startLoading() {
        loadTask?.cancel()
        guard let source = mangaDex else { return }
        let kinds = visibleKinds
        let adultFlag = adultEnabled
        loadTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for kind in kinds {
                    group.addTask {
                        await self.loadRow(kind, source: source, adult: adultFlag)
                    }
                }
            }
        }
    }

    private func loadRow(_ kind: DiscoverRowKind, source: MangaDexSource, adult adultFlag: Bool) async {
        let key = kind.cacheKey(adult: adultFlag)
        let sourceId = source.id
        let cache = self.cache

        updateRow(kind) { $0.state = .loading }
        if row(kind).items.isEmpty {
            let cached = await Task.detached(priority: .userInitiated) {
                cache.load(sourceId: sourceId, kind: key)
            }.value
            guard isCurrent(adultFlag) else { return }
            if let cached, !cached.items.isEmpty, row(kind).items.isEmpty {
                updateRow(kind) { $0.items = cached.items }
            }
        }

        do {
            let page = try await Self.fetch(kind, from: source)
            guard isCurrent(adultFlag) else { return }
            setRow(kind, DiscoverRow(items: page.items, state: .loaded))
            Task.detached(priority: .utility) {
                cache.store(page, sourceId: sourceId, kind: key)
            }
        } catch {
            guard isCurrent(adultFlag), !(error is CancellationError) else { return }
            let message = BrowseErrorText.message(for: error)
            updateRow(kind) { $0.state = .failed(message) }
        }
    }

    /// False when the task was cancelled or the 18+ state changed while it ran.
    private func isCurrent(_ adultFlag: Bool) -> Bool {
        !Task.isCancelled && adultFlag == adultEnabled
    }

    private nonisolated static func fetch(_ kind: DiscoverRowKind, from source: MangaDexSource) async throws -> MangaPage {
        switch kind {
        case .featured: return MangaPage(items: try await source.featured(), hasNextPage: false)
        case .popular: return try await source.popular(page: 1)
        case .latest: return try await source.latest(page: 1)
        case .adult: return try await source.adultPicks(page: 1)
        }
    }

    func row(_ kind: DiscoverRowKind) -> DiscoverRow {
        switch kind {
        case .featured: return featured
        case .popular: return popular
        case .latest: return latest
        case .adult: return adult
        }
    }

    private func setRow(_ kind: DiscoverRowKind, _ row: DiscoverRow) {
        guard row != self.row(kind) else { return }
        switch kind {
        case .featured: featured = row
        case .popular: popular = row
        case .latest: latest = row
        case .adult: adult = row
        }
    }

    private func updateRow(_ kind: DiscoverRowKind, _ change: (inout DiscoverRow) -> Void) {
        var value = row(kind)
        change(&value)
        setRow(kind, value)
    }
}
