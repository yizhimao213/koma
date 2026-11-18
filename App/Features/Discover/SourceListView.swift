import SwiftUI
import KomaCore

enum SourceListKind: String, Hashable, CaseIterable, Identifiable {
    case popular, latest, adult

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popular: return "热门"
        case .latest: return "最新"
        case .adult: return "18+"
        }
    }
}

/// Paginated lists of one source. Lives in a @StateObject so pagination survives pushes.
@MainActor
final class SourceListViewModel: ObservableObject {
    let source: any MangaSource
    @Published private(set) var kind: SourceListKind
    @Published private(set) var pages: [SourceListKind: PaginationState] = [:]
    @Published private(set) var errors: [SourceListKind: String] = [:]
    @Published private(set) var adultEnabled = false

    private let cache: BrowseCache?
    private var tasks: [SourceListKind: Task<Void, Never>] = [:]
    private var configured = false

    init(source: any MangaSource, initialKind: SourceListKind, cache: BrowseCache) {
        self.source = source
        self.kind = initialKind
        // Local listings are instant and change with imports, so they are never cached.
        self.cache = source is LocalSource ? nil : cache
    }

    var isMangaDex: Bool { source is MangaDexSource }

    var availableKinds: [SourceListKind] {
        isMangaDex && adultEnabled ? SourceListKind.allCases : [.popular, .latest]
    }

    var current: PaginationState { pages[kind] ?? PaginationState() }
    var currentError: String? { errors[kind] }

    /// First appearance: applies the 18+ state and loads the selected list. Later calls are no-ops.
    func configure(showAdult: Bool) {
        guard !configured else { return }
        configured = true
        adultEnabled = showAdult
        if kind == .adult && !availableKinds.contains(.adult) { kind = .popular }
        loadFirstPageIfNeeded()
    }

    /// 18+ changed: lists depend on the content rating, so all of them are dropped and reloaded.
    func adultChanged(_ showAdult: Bool) {
        guard showAdult != adultEnabled else { return }
        adultEnabled = showAdult
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        pages = [:]
        errors = [:]
        if !availableKinds.contains(kind) { kind = .popular }
        if configured { loadFirstPageIfNeeded() }
    }

    func select(_ newKind: SourceListKind) {
        guard newKind != kind, availableKinds.contains(newKind) else { return }
        kind = newKind
        loadFirstPageIfNeeded()
    }

    func itemAppeared(at index: Int) {
        guard current.shouldLoadMore(appearingIndex: index), errors[kind] == nil else { return }
        loadNextPage(for: kind)
    }

    func retry() {
        errors[kind] = nil
        loadNextPage(for: kind)
    }

    func refresh() async {
        let target = kind
        tasks[target]?.cancel()
        var state = pages[target] ?? PaginationState()
        let page = state.beginRefresh()
        pages[target] = state
        errors[target] = nil
        let task = makeLoadTask(kind: target, page: page)
        tasks[target] = task
        await task.value
    }

    // MARK: - Loading

    private func loadFirstPageIfNeeded() {
        let target = kind
        guard pages[target] == nil else { return }
        var state = PaginationState()
        if let cache, let key = cacheKey(for: target), let cached = cache.load(sourceId: source.id, kind: key) {
            state.seed(with: cached)
        }
        pages[target] = state
        loadNextPage(for: target)
    }

    private func loadNextPage(for target: SourceListKind) {
        var state = pages[target] ?? PaginationState()
        guard let page = state.beginNextPage() else { return }
        pages[target] = state
        errors[target] = nil
        tasks[target] = makeLoadTask(kind: target, page: page)
    }

    private func makeLoadTask(kind target: SourceListKind, page: Int) -> Task<Void, Never> {
        let source = self.source
        let adultFlag = adultEnabled
        return Task {
            do {
                let result = try await Self.fetch(source: source, kind: target, page: page)
                guard !Task.isCancelled, adultFlag == adultEnabled else { return }
                var state = pages[target] ?? PaginationState()
                state.finish(page: page, with: result)
                pages[target] = state
                if page == 1, let cache, let key = cacheKey(for: target) {
                    let sourceId = source.id
                    Task.detached(priority: .utility) {
                        cache.store(result, sourceId: sourceId, kind: key)
                    }
                }
            } catch {
                guard !Task.isCancelled, adultFlag == adultEnabled, !(error is CancellationError) else { return }
                var state = pages[target] ?? PaginationState()
                state.fail()
                pages[target] = state
                errors[target] = BrowseErrorText.message(for: error)
            }
        }
    }

    /// Cache keys shared with Discover (page 1 only).
    private func cacheKey(for target: SourceListKind) -> String? {
        switch target {
        case .popular: return BrowseCacheKey.list("popular", adult: adultEnabled)
        case .latest: return BrowseCacheKey.list("latest", adult: adultEnabled)
        case .adult: return adultEnabled ? BrowseCacheKey.adult : nil
        }
    }

    private nonisolated static func fetch(source: any MangaSource, kind: SourceListKind, page: Int) async throws -> MangaPage {
        switch kind {
        case .popular:
            return try await source.popular(page: page)
        case .latest:
            return try await source.latest(page: page)
        case .adult:
            guard let mangaDex = source as? MangaDexSource else { throw SourceError.unsupported }
            return try await mangaDex.adultPicks(page: page)
        }
    }
}

/// Three-column grid of one source with 热门 / 最新 (/ 18+) segments and infinite scroll.
struct SourceListView: View {
    typealias Kind = SourceListKind

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm: SourceListViewModel

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)

    init(source: any MangaSource, initialKind: Kind, cache: BrowseCache) {
        _vm = StateObject(wrappedValue: SourceListViewModel(source: source, initialKind: initialKind, cache: cache))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if vm.availableKinds.count > 1 {
                    Picker("列表", selection: kindBinding) {
                        ForEach(vm.availableKinds) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                }
                content
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await vm.refresh() }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(vm.source.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.configure(showAdult: settings.showAdult) }
        .onChange(of: settings.showAdult) { vm.adultChanged($0) }
    }

    private var kindBinding: Binding<Kind> {
        Binding(get: { vm.kind }, set: { vm.select($0) })
    }

    @ViewBuilder
    private var content: some View {
        let state = vm.current
        if state.isEmpty {
            if let error = vm.currentError {
                RetryView(message: error) { vm.retry() }
                    .padding(.top, 40)
            } else if state.isLoading || state.hasNextPage {
                skeletonGrid
            } else {
                EmptyStateView(symbol: "books.vertical", title: "这里还没有漫画", actionTitle: nil, action: nil)
                    .frame(minHeight: 360)
            }
        } else {
            grid(state)
            footer(state)
        }
    }

    private func grid(_ state: PaginationState) -> some View {
        LazyVGrid(columns: Self.columns, spacing: 18) {
            ForEach(Array(state.items.enumerated()), id: \.element) { index, item in
                NavigationLink(value: DiscoverRoute.manga(item)) {
                    CoverCard(item: item)
                }
                .buttonStyle(.pressable)
                .fadeInOnAppear(once: "grid-\(item.sourceId)-\(item.id)")
                .onAppear { vm.itemAppeared(at: index) }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func footer(_ state: PaginationState) -> some View {
        if let error = vm.currentError {
            VStack(spacing: 10) {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Theme.haptic()
                    vm.retry()
                } label: {
                    Text("重试")
                        .font(Theme.Typography.footnote)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.Palette.elevated))
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        } else if state.isLoading {
            ProgressView()
                .padding(.vertical, 16)
        } else if !state.hasNextPage {
            Text("已经到底了")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.muted)
                .padding(.vertical, 16)
        }
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: 18) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonView()
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    SkeletonView(shape: .capsule)
                        .frame(height: 10)
                        .padding(.trailing, 16)
                }
            }
        }
        .padding(.horizontal, 16)
        .accessibilityLabel("正在加载")
    }
}
