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
    private var observeTask: Task<Void, Never>?

    init(library: LibraryRepository) {
        self.library = library
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
