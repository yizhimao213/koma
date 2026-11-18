import Combine
import Foundation

public enum ReaderItem: Hashable {
    case page(chapterId: String, PageRef)
    case transition(from: Chapter, to: Chapter?)
}

public enum ReaderSessionError: Error, Equatable {
    case unknownChapter(String)
}

@MainActor
public final class ReaderSession: ObservableObject {
    @Published public private(set) var items: [ReaderItem] = []
    @Published public private(set) var currentIndex: Int = 0

    private let chapters: [Chapter]
    private let startChapterId: String
    private let startPage: Int
    private let loadPages: (Chapter) async throws -> [PageRef]

    /// Chapters that are loaded or currently loading.
    private var requestedChapterIds: Set<String> = []
    private var pageCounts: [String: Int] = [:]
    private var lastLoadedChapterOrder: Int?

    public init(
        chapters: [Chapter],
        startChapterId: String,
        startPage: Int,
        loadPages: @escaping (Chapter) async throws -> [PageRef]
    ) {
        self.chapters = chapters
        self.startChapterId = startChapterId
        self.startPage = startPage
        self.loadPages = loadPages
    }

    public func start() async throws {
        try await load(chapterId: startChapterId, page: startPage)
    }

    public func jump(toChapter id: String) async throws {
        try await load(chapterId: id, page: 0)
    }

    public func didShow(index: Int) async {
        guard index >= 0, index < items.count else { return }
        currentIndex = index
        guard index >= items.count - 3,
              let last = lastLoadedChapterOrder,
              last + 1 < chapters.count else { return }
        let next = chapters[last + 1]
        guard !requestedChapterIds.contains(next.id) else { return }
        requestedChapterIds.insert(next.id)
        do {
            let pages = try await loadPages(next)
            // A jump during the await resets state; only append if still the expected successor.
            guard lastLoadedChapterOrder == last else { return }
            append(chapter: next, order: last + 1, pages: pages)
        } catch {
            requestedChapterIds.remove(next.id)
        }
    }

    public var currentChapter: Chapter? {
        guard items.indices.contains(currentIndex) else { return nil }
        switch items[currentIndex] {
        case .page(let chapterId, _):
            return chapters.first { $0.id == chapterId }
        case .transition:
            return nil
        }
    }

    public var currentProgress: ReadingProgress? {
        guard items.indices.contains(currentIndex),
              case .page(let chapterId, let page) = items[currentIndex] else { return nil }
        return ReadingProgress(
            chapterId: chapterId,
            pageIndex: page.index,
            pageCount: pageCounts[chapterId] ?? 0,
            updatedAt: Date())
    }

    // MARK: - Private

    private func load(chapterId: String, page: Int) async throws {
        guard let order = chapters.firstIndex(where: { $0.id == chapterId }) else {
            throw ReaderSessionError.unknownChapter(chapterId)
        }
        let chapter = chapters[order]
        let pages = try await loadPages(chapter)
        items = []
        requestedChapterIds = [chapter.id]
        pageCounts = [:]
        lastLoadedChapterOrder = nil
        append(chapter: chapter, order: order, pages: pages)
        currentIndex = pages.isEmpty ? 0 : min(max(page, 0), pages.count - 1)
    }

    private func append(chapter: Chapter, order: Int, pages: [PageRef]) {
        pageCounts[chapter.id] = pages.count
        var newItems = pages.map { ReaderItem.page(chapterId: chapter.id, $0) }
        let next = order + 1 < chapters.count ? chapters[order + 1] : nil
        newItems.append(.transition(from: chapter, to: next))
        items.append(contentsOf: newItems)
        lastLoadedChapterOrder = order
    }
}
