import SwiftUI
import UniformTypeIdentifiers
import KomaCore

private struct ContinueRoute: Identifiable {
    let id = UUID()
    let item: HistoryItem
}

struct LibraryView: View {
    @Environment(\.accentColor) private var accent
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var vm: LibraryViewModel
    @AppStorage("library.columns") private var columns = 3
    @Namespace private var heroNamespace
    @State private var selected: LibraryEntry?
    @State private var readerRoute: ContinueRoute?
    @State private var showImporter = false
    @State private var showNewCategory = false
    @State private var searching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private static let horizontalPadding: CGFloat = 16
    private static let gridSpacing: CGFloat = 12

    init(env: AppEnvironment) {
        _vm = StateObject(wrappedValue: LibraryViewModel(
            library: env.library, history: env.history, updater: env.updater, toast: env.toast))
    }

    private static let importTypes: [UTType] = [.zip, .pdf, .folder, UTType(filenameExtension: "cbz") ?? .zip]

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            GeometryReader { proxy in
                scrollContent(width: proxy.size.width)
            }
            if env.importingCount > 0 {
                importingBadge
            }
            if let item = selected {
                MangaDetailView(ref: item.ref, env: env, namespace: heroNamespace, onClose: closeDetail)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(Theme.spring, value: env.importingCount > 0)
        .tabBarHidden(selected != nil || readerRoute != nil)
        .onAppear { vm.reloadContinue() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.importTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                env.importAndReport(urls)
            }
        }
        .sheet(isPresented: $showNewCategory) {
            NewCategorySheet { name in vm.addCategory(name: name) }
        }
        .fullScreenCover(item: $readerRoute, onDismiss: { vm.reloadContinue() }) { route in
            ReaderContainerView(
                manga: route.item.ref,
                chapters: route.item.chapters,
                startChapterId: route.item.progress.chapterId,
                startPage: route.item.progress.pageIndex)
            .environment(\.accentColor, accent)
        }
    }

    // MARK: - Layout

    private var displayedItems: [LibraryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return vm.items }
        return vm.items.filter { $0.ref.title.localizedCaseInsensitiveContains(query) }
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scrollContent(width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if searching {
                    searchField
                        .padding(.horizontal, Self.horizontalPadding)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                categoryChips
                if let item = vm.continueItem, vm.categoryId == nil, !isFiltering {
                    continueCard(item)
                        .padding(.horizontal, Self.horizontalPadding)
                        .padding(.bottom, 20)
                        .transition(.opacity)
                }
                gridSection(width: width)
            }
            .animation(Theme.spring, value: searching)
            .animation(Theme.spring, value: vm.continueItem?.id)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await vm.refreshLibrary() }
    }

    private var importingBadge: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在导入…")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Palette.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .cardSurface(fill: Theme.Palette.elevated)
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .transition(.opacity)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("书架")
                .font(Theme.Typography.largeTitle)
                .foregroundColor(Theme.Palette.primary)
            Spacer(minLength: 8)
            headerButton(symbol: searching ? "xmark" : "magnifyingglass", label: searching ? "关闭搜索" : "搜索") {
                if searching {
                    searchText = ""
                    searchFocused = false
                    searching = false
                } else {
                    searching = true
                    searchFocused = true
                }
            }
            optionsMenu
            headerButton(symbol: "plus", label: "导入") { showImporter = true }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private func headerButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Theme.haptic()
            action()
        } label: {
            headerIcon(symbol)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    private func headerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Theme.Palette.primary)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Theme.Palette.card))
            .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: Theme.hairlineWidth))
    }

    private var optionsMenu: some View {
        Menu {
            Picker("排序", selection: $vm.sort) {
                ForEach(LibrarySortOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Menu {
                Picker("列数", selection: $columns) {
                    Text("2 列").tag(2)
                    Text("3 列").tag(3)
                    Text("4 列").tag(4)
                }
            } label: {
                Label("列数", systemImage: "square.grid.3x3")
            }
        } label: {
            headerIcon("line.3.horizontal.decrease")
        }
        .accessibilityLabel("排序与布局")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.Palette.muted)
            TextField("搜索书架", text: $searchText)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Palette.primary)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.Palette.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .cardSurface(cornerRadius: 12)
    }

    // MARK: - Category chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", isSelected: vm.categoryId == nil) { vm.categoryId = nil }
                ForEach(vm.categories, id: \.id) { category in
                    chip(title: category.name, isSelected: vm.categoryId == category.id) {
                        vm.categoryId = category.id
                    }
                }
                Button {
                    Theme.haptic()
                    showNewCategory = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Palette.secondary)
                        .frame(width: 34, height: 32)
                        .background(Capsule().fill(Theme.Palette.card))
                        .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: Theme.hairlineWidth))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("新建分类")
            }
            .padding(.horizontal, Self.horizontalPadding)
        }
        .padding(.bottom, 18)
    }

    /// Selected chip is inverted (primary fill, background-colored text).
    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Theme.haptic()
            withAnimation(Theme.spring) { action() }
        } label: {
            Text(title)
                .font(Theme.Typography.footnote)
                .foregroundColor(isSelected ? Theme.Palette.background : Theme.Palette.secondary)
                .padding(.horizontal, 15)
                .frame(height: 32)
                .background(Capsule().fill(isSelected ? Theme.Palette.primary : Theme.Palette.card))
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : Theme.Palette.hairline,
                        lineWidth: Theme.hairlineWidth))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Continue reading

    private func continueCard(_ item: HistoryItem) -> some View {
        let total = max(item.progress.pageCount, 1)
        let current = min(item.progress.pageIndex + 1, total)
        let fraction = CGFloat(current) / CGFloat(total)
        return Button {
            Theme.haptic()
            readerRoute = ContinueRoute(item: item)
        } label: {
            HStack(spacing: 14) {
                CoverImageView(url: item.ref.coverURL, size: CGSize(width: 56, height: 84))
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text("继续阅读")
                        .font(Theme.Typography.caption)
                        .foregroundColor(accent)
                    Text("\(item.ref.title) · \(item.chapterTitle)")
                        .font(Theme.Typography.body.weight(.medium))
                        .foregroundColor(Theme.Palette.primary)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        GeometryReader { bar in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.Palette.hairline)
                                Capsule().fill(accent)
                                    .frame(width: max(bar.size.width * fraction, 3))
                            }
                        }
                        .frame(height: 3)
                        Text("\(current) / \(total)")
                            .font(Theme.Typography.caption.monospacedDigit())
                            .foregroundColor(Theme.Palette.secondary)
                            .fixedSize()
                    }
                    .padding(.top, 2)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .offset(x: 1)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(accent))
                    .shadow(color: accent.opacity(0.35), radius: 10, y: 4)
            }
            .padding(12)
            .cardSurface()
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("继续阅读 \(item.ref.title) \(item.chapterTitle)，第 \(current) 页，共 \(total) 页")
    }

    // MARK: - Grid

    @ViewBuilder
    private func gridSection(width: CGFloat) -> some View {
        let cellSize = coverDecodeSize(width: width)
        if !vm.hasLoaded {
            skeletonGrid(cellSize: cellSize)
        } else if vm.items.isEmpty {
            emptyState
                .frame(minHeight: 380)
        } else if displayedItems.isEmpty {
            Text("没有找到相关漫画")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(displayedItems) { item in
                    cell(for: item, decodeSize: cellSize)
                        .fadeInOnAppear(once: item.id)
                }
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.bottom, 24)
            .animation(Theme.spring, value: columns)
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.gridSpacing), count: max(columns, 1))
    }

    /// Cover decode target in points for the current column count (2:3 aspect).
    private func coverDecodeSize(width: CGFloat) -> CGSize {
        let count = CGFloat(max(columns, 1))
        let available = width - Self.horizontalPadding * 2 - Self.gridSpacing * (count - 1)
        let cellWidth = max((available / count).rounded(.up), 60)
        return CGSize(width: cellWidth, height: (cellWidth * 1.5).rounded(.up))
    }

    private func skeletonGrid(cellSize: CGSize) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 20) {
            ForEach(0..<(max(columns, 1) * 3), id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonView(shape: .rounded(Theme.coverRadius))
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    SkeletonView(shape: .capsule)
                        .frame(width: cellSize.width * 0.7, height: 10)
                }
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
    }

    private var emptyState: some View {
        Group {
            if vm.categoryId == nil {
                EmptyStateView(
                    symbol: "books.vertical",
                    title: "还没有漫画",
                    actionTitle: "导入本地漫画",
                    action: { showImporter = true })
            } else {
                EmptyStateView(symbol: "books.vertical", title: "这个分类还没有漫画", actionTitle: nil, action: nil)
            }
        }
    }

    private func cell(for item: LibraryEntry, decodeSize: CGSize) -> some View {
        Button {
            Theme.haptic()
            searchFocused = false
            withAnimation(Theme.spring) { selected = item }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CoverImageView(url: item.ref.coverURL, size: decodeSize)
                    .matchedGeometryEffect(id: item.id, in: heroNamespace, isSource: selected?.id != item.id)
                    .overlay(alignment: .topTrailing) {
                        if item.unreadCount > 0 {
                            Text(item.unreadCount > 99 ? "99+" : "\(item.unreadCount)")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Capsule().fill(accent))
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                                .padding(6)
                                .accessibilityLabel("\(item.unreadCount) 话未读")
                        }
                    }
                Text(item.ref.title)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Palette.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.pressable)
        .contextMenu {
            Button {
                vm.markAllRead(item)
            } label: {
                Label("标记已读", systemImage: "checkmark.circle")
            }
            Menu {
                Button("无分类") { vm.move(item, toCategory: nil) }
                ForEach(vm.categories, id: \.id) { category in
                    Button(category.name) { vm.move(item, toCategory: category.id) }
                }
            } label: {
                Label("移动分类", systemImage: "folder")
            }
            Button(role: .destructive) {
                vm.removeFromLibrary(item)
            } label: {
                Label("移出书架", systemImage: "trash")
            }
        }
    }

    private func closeDetail() {
        withAnimation(Theme.spring) { selected = nil }
        vm.reloadContinue()
    }
}

private struct NewCategorySheet: View {
    @Environment(\.accentColor) private var accent
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("新建分类")
                .font(Theme.Typography.title)
                .foregroundColor(Theme.Palette.primary)
            TextField("分类名称", text: $name)
                .font(Theme.Typography.body)
                .focused($focused)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .cardSurface(cornerRadius: 12, fill: Theme.Palette.elevated)
                .submitLabel(.done)
                .onSubmit(create)
            Button(action: create) {
                Text("创建")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(.pressable)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.card.ignoresSafeArea())
        .presentationDetents([.height(240)])
        .onAppear { focused = true }
    }

    private func create() {
        onCreate(name)
        dismiss()
    }
}
