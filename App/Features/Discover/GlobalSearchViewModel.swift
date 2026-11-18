import SwiftUI
import KomaCore

/// Searches every registered source concurrently, debounced, with results grouped by source.
@MainActor
final class GlobalSearchViewModel: ObservableObject {
    enum SectionState: Equatable {
        case loading
        case loaded([MangaRef])
        case failed(String)
    }

    struct Section: Identifiable, Equatable {
        let id: String
        let name: String
        var state: SectionState
    }

    static let debounceNanoseconds: UInt64 = 400_000_000

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }
    @Published private(set) var sections: [Section] = []

    private let sources: [any MangaSource]
    private var searchTask: Task<Void, Never>?
    private var retryTasks: [String: Task<Void, Never>] = [:]
    private var activeQuery = ""

    init(sources: [any MangaSource]) {
        self.sources = sources
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Search immediately (keyboard return key), skipping the debounce.
    func submit() {
        startSearch(debounce: false)
    }

    /// Re-runs the current query for one source after an inline failure.
    func retry(sourceId: String) {
        guard !activeQuery.isEmpty, let source = sources.first(where: { $0.id == sourceId }) else { return }
        let text = activeQuery
        update(sourceId, .loading)
        retryTasks[sourceId]?.cancel()
        retryTasks[sourceId] = Task {
            let state = await Self.search(source, query: text)
            guard !Task.isCancelled, text == activeQuery, let state else { return }
            update(sourceId, state)
        }
    }

    func cancel() {
        searchTask?.cancel()
        retryTasks.values.forEach { $0.cancel() }
        retryTasks = [:]
    }

    // MARK: - Private

    private func scheduleSearch() {
        startSearch(debounce: true)
    }

    private func startSearch(debounce: Bool) {
        let text = trimmedQuery
        // Return key on a query that is already shown (or running): keep the current results.
        if !debounce && text == activeQuery && !sections.isEmpty { return }
        cancel()
        guard !text.isEmpty else {
            activeQuery = ""
            sections = []
            return
        }
        let sources = self.sources
        searchTask = Task {
            if debounce {
                do {
                    try await Task.sleep(nanoseconds: Self.debounceNanoseconds)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            activeQuery = text
            sections = sources.map { Section(id: $0.id, name: $0.name, state: .loading) }
            await withTaskGroup(of: (String, SectionState?).self) { group in
                for source in sources {
                    group.addTask {
                        (source.id, await Self.search(source, query: text))
                    }
                }
                for await (sourceId, state) in group {
                    guard !Task.isCancelled else { break }
                    if let state { update(sourceId, state) }
                }
            }
        }
    }

    private func update(_ sourceId: String, _ state: SectionState) {
        guard let index = sections.firstIndex(where: { $0.id == sourceId }) else { return }
        sections[index].state = state
    }

    /// Returns nil when cancelled so a superseded search never shows an error.
    private nonisolated static func search(_ source: any MangaSource, query: String) async -> SectionState? {
        do {
            let page = try await source.search(query: query, filters: [:], page: 1)
            return .loaded(page.items)
        } catch {
            if error is CancellationError || Task.isCancelled { return nil }
            if let urlError = error as? URLError, urlError.code == .cancelled { return nil }
            return .failed(BrowseErrorText.message(for: error))
        }
    }
}
