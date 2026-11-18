import Foundation
import KomaCore

@MainActor
final class MangaDetailViewModel: ObservableObject {
    let ref: MangaRef
    @Published private(set) var details: MangaDetails?
    /// Chapters in ascending reading order.
    @Published private(set) var chapters: [Chapter] = []
    @Published private(set) var readIds: Set<String> = []
    @Published private(set) var progress: ReadingProgress?
    @Published private(set) var inLibrary = false
    @Published private(set) var isLoading = true
    @Published private(set) var errorText: String?

    private let library: LibraryRepository
    private let history: HistoryRepository
    private let sources: SourceRegistry

    init(ref: MangaRef, env: AppEnvironment) {
        self.ref = ref
        self.library = env.library
        self.history = env.history
        self.sources = env.sources
    }

    func load() async {
        guard let source = sources.source(id: ref.sourceId) else {
            errorText = "找不到漫画来源"
            isLoading = false
            return
        }
        do {
            let loadedDetails = try await source.details(for: ref)
            let loadedChapters = try await source.chapters(for: ref)
            try library.upsert(details: loadedDetails, chapters: loadedChapters)
            details = loadedDetails
            chapters = loadedChapters.sorted { $0.index < $1.index }
            errorText = nil
        } catch {
            errorText = "加载失败"
        }
        refreshState()
        isLoading = false
    }

    /// Re-reads read flags, progress and library membership (e.g. after the reader closes).
    func refreshState() {
        readIds = Set(chapters.filter { (try? library.isRead($0)) == true }.map(\.id))
        progress = try? history.progress(for: ref)
        let items = (try? library.items(categoryId: nil, sort: .added)) ?? []
        inLibrary = items.contains { $0.ref.sourceId == ref.sourceId && $0.ref.id == ref.id }
    }

    func toggleLibrary() {
        let target = !inLibrary
        try? library.setInLibrary(ref, target)
        inLibrary = target
    }

    func setRead(_ chapter: Chapter, _ read: Bool) {
        try? library.markRead([chapter], read)
        if read { readIds.insert(chapter.id) } else { readIds.remove(chapter.id) }
    }

    /// Where the primary button should open the reader.
    var resumeTarget: (chapter: Chapter, page: Int)? {
        guard let first = chapters.first else { return nil }
        guard let progress, let current = chapters.first(where: { $0.id == progress.chapterId }) else {
            return (first, 0)
        }
        if progress.pageCount > 0, progress.pageIndex >= progress.pageCount - 1 {
            let next = chapters.first { $0.index > current.index }
            if let next { return (next, 0) }
            return (current, 0)
        }
        return (current, progress.pageIndex)
    }

    var hasProgress: Bool {
        guard let progress else { return false }
        return chapters.contains { $0.id == progress.chapterId }
    }

    func resumeLabel() -> String {
        guard hasProgress, let target = resumeTarget else { return "开始阅读" }
        if let number = target.chapter.number {
            let text = number == number.rounded() ? String(Int(number)) : String(number)
            return "继续阅读 第\(text)话"
        }
        return "继续阅读 \(target.chapter.title)"
    }

    /// Page to open when tapping a chapter row (resumes mid-chapter if it is the one in progress).
    func startPage(for chapter: Chapter) -> Int {
        guard let progress, progress.chapterId == chapter.id,
              progress.pageCount > 0, progress.pageIndex < progress.pageCount - 1
        else { return 0 }
        return progress.pageIndex
    }
}
