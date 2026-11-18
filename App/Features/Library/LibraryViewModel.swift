import Foundation
import KomaCore

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case lastRead, added, title, unread

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastRead: return "最近阅读"
        case .added: return "最近添加"
        case .title: return "名称"
        case .unread: return "未读"
        }
    }

    var core: LibrarySort {
        switch self {
        case .lastRead: return .lastRead
        case .added: return .added
        case .title: return .title
        case .unread: return .unread
        }
    }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [LibraryEntry] = []
    @Published private(set) var categories: [CategoryRecord] = []
    @Published private(set) var hasLoaded = false
    /// Most recent history entry whose chapter still resolves; drives the 继续阅读 card.
    @Published private(set) var continueItem: HistoryItem?
    @Published var categoryId: Int64? {
        didSet { if oldValue != categoryId { restartObservation() } }
    }
    @Published var sort: LibrarySortOption {
        didSet {
            guard oldValue != sort else { return }
            UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey)
            restartObservation()
        }
    }

    private static let sortKey = "library.sort"
    private let library: LibraryRepository
    private let history: HistoryRepository
    private let updater: LibraryUpdater
    private let toast: ToastCenter
    private var observeTask: Task<Void, Never>?
    private var continueToken = 0

    init(library: LibraryRepository, history: HistoryRepository, updater: LibraryUpdater, toast: ToastCenter) {
        self.library = library
        self.history = history
        self.updater = updater
        self.toast = toast
        let stored = UserDefaults.standard.string(forKey: Self.sortKey)
        self.sort = stored.flatMap(LibrarySortOption.init(rawValue:)) ?? .lastRead
        reloadCategories()
        restartObservation()
    }

    func reloadCategories() {
        categories = (try? library.categories()) ?? []
    }

    func addCategory(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? library.addCategory(name: trimmed)
        reloadCategories()
    }

    func markAllRead(_ item: LibraryEntry) {
        guard let chapters = try? library.chapters(for: item.ref) else { return }
        try? library.markRead(chapters, true)
    }

    func move(_ item: LibraryEntry, toCategory id: Int64?) {
        try? library.assign(item.ref, to: id.map { [$0] } ?? [])
    }

    func removeFromLibrary(_ item: LibraryEntry) {
        try? library.setInLibrary(item.ref, false)
    }

    /// Reloads the continue-reading entry off the main thread.
    func reloadContinue() {
        continueToken += 1
        let token = continueToken
        let history = self.history
        let library = self.library
        Task {
            let item = await Task.detached(priority: .userInitiated) { () -> HistoryItem? in
                let recent = (try? history.recent(limit: 20)) ?? []
                for entry in recent {
                    let chapters = ((try? library.chapters(for: entry.0)) ?? []).sorted { $0.index < $1.index }
                    if chapters.contains(where: { $0.id == entry.1.chapterId }) {
                        return HistoryItem(ref: entry.0, progress: entry.1, chapters: chapters)
                    }
                }
                return nil
            }.value
            // Publish only real changes so tab switches and hero transitions don't re-render the view.
            guard token == continueToken, item != continueItem else { return }
            continueItem = item
        }
    }

    /// Checks every library title for new chapters and reports the outcome with a toast.
    func refreshLibrary() async {
        let result = await updater.refreshAll()
        toast.show(Self.refreshMessage(for: result))
        reloadContinue()
    }

    static func refreshMessage(for result: LibraryUpdateResult) -> String {
        let updated = result.updatedMangaCount
        let failed = result.failedCount
        if updated > 0 && failed > 0 {
            return "\(updated) 部漫画有更新，\(failed) 部失败"
        } else if updated > 0 {
            return "\(updated) 部漫画有更新"
        } else if failed > 0 {
            return "\(failed) 部更新失败"
        } else {
            return "已是最新"
        }
    }

    private func restartObservation() {
        observeTask?.cancel()
        let stream = library.observeItems(categoryId: categoryId, sort: sort.core)
        observeTask = Task { [weak self] in
            for await next in stream {
                if Task.isCancelled { break }
                self?.items = next
                self?.hasLoaded = true
            }
        }
    }
}
