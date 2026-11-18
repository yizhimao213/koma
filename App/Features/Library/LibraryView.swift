import SwiftUI
import UniformTypeIdentifiers
import KomaCore

struct LibraryView: View {
    @Environment(\.accentColor) private var accent
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var vm: LibraryViewModel
    @AppStorage("library.columns") private var columns = 3
    @Namespace private var heroNamespace
    @State private var selected: LibraryEntry?
    @State private var showImporter = false
    @State private var showNewCategory = false

    init(library: LibraryRepository) {
        _vm = StateObject(wrappedValue: LibraryViewModel(library: library))
    }

    private static let importTypes: [UTType] = [.zip, .pdf, .folder, UTType(filenameExtension: "cbz") ?? .zip]

    var body: some View {
        ZStack {
            NavigationStack {
                content
                    .navigationTitle("书架")
                    .toolbar { toolbarContent }
                    .toolbar(selected == nil ? .visible : .hidden, for: .tabBar)
            }
            if let item = selected {
                MangaDetailView(ref: item.ref, env: env, namespace: heroNamespace, onClose: closeDetail)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
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
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            categoryChips
            ZStack {
                if vm.items.isEmpty && vm.hasLoaded {
                    emptyState
                } else {
                    grid
                }
                if env.importingCount > 0 {
                    ProgressView("正在导入…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .transition(.opacity)
                }
            }
            .animation(Theme.spring, value: env.importingCount > 0)
        }
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color(.secondarySystemFill)))
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Theme.haptic()
            withAnimation(Theme.spring) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? accent : Color(.secondarySystemFill)))
        }
        .buttonStyle(.pressable)
    }

    private var grid: some View {
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
        return ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(vm.items) { item in
                    cell(for: item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .animation(Theme.spring, value: columns)
        }
    }

    private func cell(for item: LibraryEntry) -> some View {
        Button {
            Theme.haptic()
            withAnimation(Theme.spring) { selected = item }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CoverImageView(url: item.ref.coverURL, size: CGSize(width: 240, height: 360))
                    .matchedGeometryEffect(id: item.id, in: heroNamespace, isSource: selected?.id != item.id)
                    .overlay(alignment: .topTrailing) {
                        if item.unreadCount > 0 {
                            Text("\(item.unreadCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(accent))
                                .padding(6)
                        }
                    }
                Text(item.ref.title)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.primary)
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Menu {
                Picker("列数", selection: $columns) {
                    Text("2 列").tag(2)
                    Text("3 列").tag(3)
                    Text("4 列").tag(4)
                }
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            Menu {
                Picker("排序", selection: $vm.sort) {
                    ForEach(LibrarySortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            Button {
                Theme.haptic()
                showImporter = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private func closeDetail() {
        withAnimation(Theme.spring) { selected = nil }
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
                .font(.headline)
            TextField("分类名称", text: $name)
                .focused($focused)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemFill)))
                .submitLabel(.done)
                .onSubmit(create)
            Button(action: create) {
                Text("创建")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(.pressable)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .presentationDetents([.height(240)])
        .onAppear { focused = true }
    }

    private func create() {
        onCreate(name)
        dismiss()
    }
}
