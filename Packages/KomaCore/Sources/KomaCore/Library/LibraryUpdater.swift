import Foundation

public struct LibraryUpdateResult: Equatable, Sendable {
    public var updatedMangaCount: Int
    public var newChapterCount: Int
    public var failedCount: Int

    public init(updatedMangaCount: Int, newChapterCount: Int, failedCount: Int) {
        self.updatedMangaCount = updatedMangaCount
        self.newChapterCount = newChapterCount
        self.failedCount = failedCount
    }
}

/// Refreshes every non-local library manga from its source, pruning chapters that disappeared.
public final class LibraryUpdater: @unchecked Sendable {
    private let library: LibraryRepository
    private let sources: SourceRegistry
    private let maxConcurrent: Int

    public init(library: LibraryRepository, sources: SourceRegistry, maxConcurrent: Int = 3) {
        self.library = library
        self.sources = sources
        self.maxConcurrent = max(1, maxConcurrent)
    }

    private enum Outcome: Sendable {
        case unchanged
        case updated(newChapters: Int)
        case failed
    }

    public func refreshAll() async -> LibraryUpdateResult {
        let refs: [MangaRef]
        do {
            refs = try library.libraryRefs()
        } catch {
            return LibraryUpdateResult(updatedMangaCount: 0, newChapterCount: 0, failedCount: 0)
        }

        var jobs: [(MangaRef, any MangaSource)] = []
        var failed = 0
        for ref in refs where ref.sourceId != "local" {
            if let source = sources.source(id: ref.sourceId) {
                jobs.append((ref, source))
            } else {
                failed += 1
            }
        }

        var updated = 0
        var newChapters = 0
        let library = self.library
        let limit = maxConcurrent

        await withTaskGroup(of: Outcome.self) { group in
            var next = 0
            var inFlight = 0
            while inFlight < limit && next < jobs.count {
                let (ref, source) = jobs[next]
                next += 1
                inFlight += 1
                group.addTask { await LibraryUpdater.refresh(ref: ref, source: source, library: library) }
            }
            while inFlight > 0 {
                guard let outcome = await group.next() else { break }
                inFlight -= 1
                switch outcome {
                case .unchanged:
                    break
                case .updated(let count):
                    updated += 1
                    newChapters += count
                case .failed:
                    failed += 1
                }
                if next < jobs.count {
                    let (ref, source) = jobs[next]
                    next += 1
                    inFlight += 1
                    group.addTask { await LibraryUpdater.refresh(ref: ref, source: source, library: library) }
                }
            }
        }

        return LibraryUpdateResult(updatedMangaCount: updated, newChapterCount: newChapters, failedCount: failed)
    }

    private static func refresh(ref: MangaRef, source: any MangaSource, library: LibraryRepository) async -> Outcome {
        do {
            let details = try await source.details(for: ref)
            let chapters = try await source.chapters(for: ref)
            let before = try library.chapterIds(for: ref)
            try library.upsert(details: details, chapters: chapters, pruneMissing: true)
            let added = chapters.filter { !before.contains($0.id) }.count
            return added > 0 ? .updated(newChapters: added) : .unchanged
        } catch {
            return .failed
        }
    }
}
