import SwiftUI
import KomaCore

struct HistoryItem: Identifiable {
    let ref: MangaRef
    let progress: ReadingProgress
    let chapters: [Chapter]

    var id: String { "\(ref.sourceId)/\(ref.id)" }

    var chapterTitle: String {
        chapters.first { $0.id == progress.chapterId }?.title ?? "未知章节"
    }

    var detailText: String {
        let total = max(progress.pageCount, 1)
        let current = min(progress.pageIndex + 1, total)
        return "读到 \(chapterTitle) 第 \(current)/\(total) 页"
    }
}

private struct HistorySection: Identifiable {
    let title: String
    let items: [HistoryItem]
    var id: String { title }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var loaded = false

    private let history: HistoryRepository
    private let library: LibraryRepository

    init(env: AppEnvironment) {
        history = env.history
        library = env.library
    }

    func reload() {
        let history = self.history
        let library = self.library
        Task {
            let loadedItems = await Task.detached(priority: .userInitiated) { () -> [HistoryItem] in
                let recent = (try? history.recent(limit: 200)) ?? []
                return recent.map { entry in
                    HistoryItem(
                        ref: entry.0, progress: entry.1,
                        chapters: ((try? library.chapters(for: entry.0)) ?? []).sorted { $0.index < $1.index })
                }
            }.value
            items = loadedItems
            loaded = true
        }
    }

    func delete(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        let history = self.history
        let ref = item.ref
        Task.detached(priority: .utility) {
            try? history.delete(ref)
        }
    }
}

private struct HistoryRoute: Identifiable {
    let id = UUID()
    let item: HistoryItem
}

struct HistoryView: View {
    @Environment(\.accentColor) private var accent
    @StateObject private var vm: HistoryViewModel
    @State private var route: HistoryRoute?

    init(env: AppEnvironment) {
        _vm = StateObject(wrappedValue: HistoryViewModel(env: env))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty {
                    if vm.loaded {
                        EmptyStateView(symbol: "clock", title: "还没有阅读记录", actionTitle: nil, action: nil)
                    } else {
                        Color.clear
                    }
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(section.title) {
                                ForEach(section.items) { item in
                                    row(item)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("历史")
            .animation(Theme.spring, value: vm.items.map(\.id))
        }
        .onAppear { vm.reload() }
        .fullScreenCover(item: $route, onDismiss: { vm.reload() }) { route in
            ReaderContainerView(
                manga: route.item.ref,
                chapters: route.item.chapters,
                startChapterId: route.item.progress.chapterId,
                startPage: route.item.progress.pageIndex)
            .environment(\.accentColor, accent)
        }
    }

    private var sections: [HistorySection] {
        let calendar = Calendar.current
        let today = vm.items.filter { calendar.isDateInToday($0.progress.updatedAt) }
        let yesterday = vm.items.filter { calendar.isDateInYesterday($0.progress.updatedAt) }
        let earlier = vm.items.filter {
            !calendar.isDateInToday($0.progress.updatedAt) && !calendar.isDateInYesterday($0.progress.updatedAt)
        }
        return [
            HistorySection(title: "今天", items: today),
            HistorySection(title: "昨天", items: yesterday),
            HistorySection(title: "更早", items: earlier)
        ].filter { !$0.items.isEmpty }
    }

    private func row(_ item: HistoryItem) -> some View {
        let canResume = item.chapters.contains { $0.id == item.progress.chapterId }
        return Button {
            guard canResume else { return }
            Theme.haptic()
            route = HistoryRoute(item: item)
        } label: {
            HStack(spacing: 14) {
                CoverImageView(url: item.ref.coverURL, size: CGSize(width: 150, height: 225))
                    .frame(width: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.ref.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text(item.detailText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .opacity(canResume ? 1 : 0.5)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Theme.haptic()
                withAnimation(Theme.spring) { vm.delete(item) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
