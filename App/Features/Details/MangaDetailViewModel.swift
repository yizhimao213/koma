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
            details = loadedDetails
            chapters = loadedChapters.sorted { $0.index < $1.index }
            errorText = nil
            await syncDatabase(details: loadedDetails, chapters: loadedChapters)
        } catch {
            errorText = "加载失败"
        }
        isLoading = false
    }

    /// Re-reads read flags, progress and library membership (e.g. after the reader closes).
    func refreshState() {
        Task { await reloadState() }
    }

    /// Upserts off the main actor, and only when needed so the library observation
    /// does not re-emit during the hero transition.
    private func syncDatabase(details: MangaDetails, chapters: [Chapter]) async {
        let library = self.library
        let history = self.history
        let ref = self.ref
        let state = await Task.detached(priority: .userInitiated) { () -> State in
            let inLibrary = (try? library.isInLibrary(ref)) ?? false
            let known = (try? library.chapters(for: ref).count) ?? 0
            if !(inLibrary && known == chapters.count) {
                try? library.upsert(details: details, chapters: chapters)
            }
            return Self.readState(library: library, history: history, ref: ref)
        }.value
        apply(state)
    }

    private func reloadState() async {
        let library = self.library
        let history = self.history
        let ref = self.ref
        let state = await Task.detached(priority: .userInitiated) {
            Self.readState(library: library, history: history, ref: ref)
        }.value
        apply(state)
    }

    private struct State {
        var readIds: Set<String>
        var progress: ReadingProgress?
        var inLibrary: Bool
    }

    private nonisolated static func readState(
        library: LibraryRepository, history: HistoryRepository, ref: MangaRef
    ) -> State {
        State(
            readIds: (try? library.readChapterIds(for: ref)) ?? [],
            progress: try? history.progress(for: ref),
            inLibrary: (try? library.isInLibrary(ref)) ?? false)
    }

    private func apply(_ state: State) {
        readIds = state.readIds
        progress = state.progress
        inLibrary = state.inLibrary
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
