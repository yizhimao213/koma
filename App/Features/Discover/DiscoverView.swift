import SwiftUI
import KomaCore

/// Discover tab: search entry, "今日推荐" carousel, MangaDex rows and the list of sources.
struct DiscoverView: View {
    @Environment(\.accentColor) private var accent
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm: DiscoverViewModel
    @State private var path: [DiscoverRoute] = []

    init(env: AppEnvironment) {
        _vm = StateObject(wrappedValue: DiscoverViewModel(sources: env.sources, cache: env.browseCache))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    searchEntry
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    if vm.allFailedEmpty {
                        RetryView(message: vm.featured.failureMessage ?? "网络好像不太通畅") { vm.retryAll() }
                            .padding(.top, 24)
                    } else if vm.hasMangaDex {
                        if vm.hasStaleRows {
                            staleBanner
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }
                        hero
                            .padding(.bottom, 28)
                        rowSection("热门连载", kind: .popular, listKind: .popular)
                        rowSection("最近更新", kind: .latest, listKind: .latest)
                        if settings.showAdult {
                            rowSection("18+ 精选", kind: .adult, listKind: .adult)
                                .transition(.opacity)
                        }
                    }
                    sourcesSection
                }
                .padding(.bottom, 24)
                .animation(Theme.spring, value: settings.showAdult)
            }
            .refreshable { await vm.refresh() }
            .background(Theme.Palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DiscoverRoute.self) { route in
                destination(route)
            }
        }
        .onAppear { vm.loadIfNeeded(showAdult: settings.showAdult) }
        .onChange(of: settings.showAdult) { vm.adultChanged($0) }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func destination(_ route: DiscoverRoute) -> some View {
        switch route {
        case .manga(let ref):
            MangaDetailView(ref: ref, env: env)
                .tabBarHidden(true)
        case .sourceList(let sourceId, let kind):
            if let source = env.sources.source(id: sourceId) {
                SourceListView(source: source, initialKind: kind, cache: env.browseCache)
            } else {
                EmptyStateView(symbol: "questionmark.folder", title: "找不到这个漫画源", actionTitle: nil, action: nil)
            }
        case .search:
            GlobalSearchView(sources: env.sources.all)
        }
    }

    // MARK: - Header

    private var header: some View {
        Text("发现")
            .font(Theme.Typography.largeTitle)
            .foregroundColor(Theme.Palette.primary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
    }

    private var searchEntry: some View {
        Button {
            Theme.haptic()
            path.append(.search)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                Text("搜索漫画")
                    .font(Theme.Typography.body)
                Spacer(minLength: 0)
            }
            .foregroundColor(Theme.Palette.secondary)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .cardSurface(cornerRadius: 21, fill: Theme.Palette.elevated)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("搜索漫画")
    }

    private var staleBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundColor(Theme.Palette.secondary)
            Text("网络不可用，正在显示缓存内容")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Palette.secondary)
            Spacer(minLength: 8)
            Button {
                Theme.haptic()
                vm.retryAll()
            } label: {
                Text("重试")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(accent)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cardSurface(cornerRadius: 12)
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        let row = vm.featured
        if !row.items.isEmpty {
            HeroCarousel(items: row.items, details: vm.heroDetails) { vm.loadHeroDetails(for: $0) }
                .transition(.opacity)
        } else if let message = row.failureMessage {
            inlineRetry(message) { vm.retry(.featured) }
                .frame(height: HeroCarousel.height)
                .padding(.horizontal, 16)
        } else {
            SkeletonView(shape: .rounded(Theme.cardRadius))
                .frame(height: HeroCarousel.height)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)  // matches the carousel's indicator row
        }
    }

    // MARK: - Rows

    private func rowSection(_ title: String, kind: DiscoverRowKind, listKind: SourceListKind) -> some View {
        let row = vm.row(kind)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title) {
                path.append(.sourceList(sourceId: "mangadex", kind: listKind))
            }
            if !row.items.isEmpty {
                HorizontalCoverRow(items: row.items) { DiscoverRoute.manga($0) }
            } else if let message = row.failureMessage {
                inlineRetry(message) { vm.retry(kind) }
                    .padding(.horizontal, 16)
            } else {
                HorizontalCoverRowSkeleton()
            }
        }
        .padding(.bottom, 28)
    }

    private func inlineRetry(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(message)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
            Button {
                Theme.haptic()
                retry()
            } label: {
                Text("重试")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.Palette.elevated))
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        .cardSurface()
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "漫画源")
            VStack(spacing: 0) {
                let sources = env.sources.all
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    Button {
                        Theme.haptic()
                        path.append(.sourceList(sourceId: source.id, kind: .popular))
                    } label: {
                        sourceRow(source)
                    }
                    .buttonStyle(.pressable)
                    if index < sources.count - 1 {
                        Rectangle()
                            .fill(Theme.Palette.hairline)
                            .frame(height: Theme.hairlineWidth)
                            .padding(.leading, 70)
                    }
                }
            }
            .cardSurface()
            .padding(.horizontal, 16)
        }
    }

    private func sourceRow(_ source: any MangaSource) -> some View {
        let isLocal = source is LocalSource
        return HStack(spacing: 14) {
            Image(systemName: isLocal ? "folder.fill" : "globe.asia.australia.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isLocal ? Theme.Palette.muted : accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(Theme.Typography.body.weight(.medium))
                    .foregroundColor(Theme.Palette.primary)
                Text(isLocal ? "浏览已导入的漫画" : "在线漫画 · 多语言")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Palette.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
