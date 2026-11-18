import SwiftUI
import UIKit
import KomaCore

/// Full-screen reader: a UIKit page view with a SwiftUI menu overlay.
struct ReaderContainerView: View {
    let manga: MangaRef
    let chapters: [Chapter]
    let startChapterId: String
    let startPage: Int
    @EnvironmentObject private var env: AppEnvironment

    init(manga: MangaRef, chapters: [Chapter], startChapterId: String, startPage: Int) {
        self.manga = manga
        self.chapters = chapters
        self.startChapterId = startChapterId
        self.startPage = startPage
    }

    var body: some View {
        ReaderScreen(
            env: env, manga: manga, chapters: chapters,
            startChapterId: startChapterId, startPage: startPage)
    }

    /// Reading mode used when a manga has no stored preference. Task 8 redirects this to AppSettings.
    static func defaultReadingMode() -> ReadingMode {
        .rightToLeft
    }

    static func readingModeKey(for manga: MangaRef) -> String {
        "readingMode.\(manga.sourceId)/\(manga.id)"
    }
}

private struct ReaderScreen: View {
    @StateObject private var model: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    init(env: AppEnvironment, manga: MangaRef, chapters: [Chapter], startChapterId: String, startPage: Int) {
        _model = StateObject(wrappedValue: ReaderViewModel(
            manga: manga, chapters: chapters,
            startChapterId: startChapterId, startPage: startPage,
            history: env.history, sources: env.sources))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ReaderPagesRepresentable(model: model)
                .ignoresSafeArea()
            statusOverlay
            ReaderMenuView(model: model, pageState: model.pageState, onClose: close)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(!model.menuVisible)
        .persistentSystemOverlays(model.menuVisible ? .automatic : .hidden)
        .task { await model.start() }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .tint(.white)
                .allowsHitTesting(false)
        case .failed:
            VStack(spacing: 16) {
                Text("加载失败")
                    .font(.headline)
                    .foregroundColor(.white)
                HStack(spacing: 12) {
                    Button("重试") {
                        Theme.haptic()
                        Task { await model.start() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    Button("关闭") { close() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
        case .ready:
            EmptyView()
        }
    }

    private func close() {
        Theme.haptic()
        model.flushSave()
        dismiss()
    }
}

/// Serial queue so debounced saves and the final flush are written in order.
private let historySaveQueue = DispatchQueue(label: "com.koma.reader.history", qos: .utility)

/// Page/chapter position shown by the menu; split out so page changes only re-render the menu.
@MainActor
final class ReaderPageState: ObservableObject {
    @Published private(set) var chapter: Chapter?
    /// 0-based position within the chapter.
    @Published private(set) var page = 0
    @Published private(set) var count = 0

    func update(chapter: Chapter?, page: Int, count: Int) {
        if self.chapter != chapter { self.chapter = chapter }
        if self.page != page { self.page = page }
        if self.count != count { self.count = count }
    }
}

@MainActor
final class ReaderViewModel: ObservableObject, ReaderViewControllerDelegate {
    enum Phase: Equatable {
        case loading, ready, failed
    }

    let manga: MangaRef
    let chapters: [Chapter]
    let session: ReaderSession
    let pageState = ReaderPageState()

    @Published private(set) var mode: ReadingMode
    @Published private(set) var menuVisible = false
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var brightness: CGFloat = 0.5

    weak var controller: ReaderViewController?

    private let history: HistoryRepository
    private var shownIndex: Int?
    private var lastSeekPage: Int?
    private var saveWork: DispatchWorkItem?
    private var originalBrightness: CGFloat?

    init(
        manga: MangaRef, chapters: [Chapter], startChapterId: String, startPage: Int,
        history: HistoryRepository, sources: SourceRegistry
    ) {
        self.manga = manga
        self.chapters = chapters
        self.history = history
        let sourceId = manga.sourceId
        self.session = ReaderSession(
            chapters: chapters, startChapterId: startChapterId, startPage: startPage,
            loadPages: { chapter in
                guard let source = sources.source(id: sourceId) else { throw SourceError.notFound }
                return try await source.pages(for: chapter)
            })
        let stored = UserDefaults.standard.string(forKey: ReaderContainerView.readingModeKey(for: manga))
        self.mode = stored.flatMap(ReadingMode.init(rawValue:)) ?? ReaderContainerView.defaultReadingMode()
        self.pageState.update(chapter: chapters.first { $0.id == startChapterId }, page: startPage, count: 0)
    }

    // MARK: - Lifecycle

    func start() async {
        guard phase != .ready else { return }
        phase = .loading
        do {
            try await session.start()
            phase = .ready
        } catch {
            phase = .failed
        }
    }

    func onAppear() {
        UIApplication.shared.isIdleTimerDisabled = true
        if let screen = Self.screen {
            originalBrightness = screen.brightness
            brightness = screen.brightness
        }
    }

    func onDisappear() {
        flushSave()
        UIApplication.shared.isIdleTimerDisabled = false
        if let originalBrightness, let screen = Self.screen {
            screen.brightness = originalBrightness
        }
        originalBrightness = nil
    }

    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
    }

    // MARK: - Menu actions

    func setMenuVisible(_ visible: Bool) {
        guard visible != menuVisible else { return }
        withAnimation(Theme.spring) { menuVisible = visible }
    }

    func setMode(_ newMode: ReadingMode) {
        guard newMode != mode else { return }
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: ReaderContainerView.readingModeKey(for: manga))
        controller?.setMode(newMode)
    }

    func setBrightness(_ value: CGFloat) {
        brightness = value
        Self.screen?.brightness = value
    }

    /// Jumps within the current chapter to a 0-based page position (slider scrubbing).
    func seek(toPage page: Int) {
        guard page != lastSeekPage, let chapter = pageState.chapter else { return }
        lastSeekPage = page
        controller?.scrollToPage(chapterId: chapter.id, position: page)
    }

    func endSeeking() {
        lastSeekPage = nil
    }

    var previousChapter: Chapter? { neighbourChapter(offset: -1) }
    var nextChapter: Chapter? { neighbourChapter(offset: 1) }

    private func neighbourChapter(offset: Int) -> Chapter? {
        guard let current = pageState.chapter,
              let index = chapters.firstIndex(where: { $0.id == current.id }),
              chapters.indices.contains(index + offset) else { return nil }
        return chapters[index + offset]
    }

    func goTo(chapter: Chapter) {
        Task {
            try? await session.jump(toChapter: chapter.id)
        }
    }

    // MARK: - ReaderViewControllerDelegate

    var readerMenuVisible: Bool { menuVisible }

    func readerSetMenuVisible(_ visible: Bool) {
        setMenuVisible(visible)
    }

    func readerDidShow(index: Int) {
        shownIndex = index
        Task { await session.didShow(index: index) }
        updatePageState(index: index)
        scheduleSave()
    }

    private func updatePageState(index: Int) {
        let items = session.items
        guard items.indices.contains(index) else { return }
        switch items[index] {
        case .page(let chapterId, _):
            let (position, count) = Self.position(of: index, chapterId: chapterId, in: items)
            pageState.update(chapter: chapters.first { $0.id == chapterId }, page: position, count: count)
        case .transition(let from, _):
            let (_, count) = Self.position(of: index, chapterId: from.id, in: items)
            pageState.update(chapter: from, page: max(count - 1, 0), count: count)
        }
    }

    private static func position(of index: Int, chapterId: String, in items: [ReaderItem]) -> (Int, Int) {
        var first: Int?
        var count = 0
        for (i, item) in items.enumerated() {
            if case .page(let id, _) = item, id == chapterId {
                if first == nil { first = i }
                count += 1
            }
        }
        return (index - (first ?? index), count)
    }

    // MARK: - History

    /// A transition item maps to the last page of the chapter it ends, so finishing a chapter is sticky.
    private func progress(at index: Int) -> ReadingProgress? {
        session.progressForSaving(at: index)
    }

    /// Debounced (0.5 s) save of the currently shown page.
    private func scheduleSave() {
        saveWork?.cancel()
        guard let index = shownIndex, let progress = progress(at: index) else { return }
        let history = self.history
        let manga = self.manga
        let work = DispatchWorkItem {
            historySaveQueue.async {
                try? history.save(manga, progress: progress)
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Writes the current page immediately (waits for earlier queued saves).
    func flushSave() {
        saveWork?.cancel()
        saveWork = nil
        guard let index = shownIndex, let progress = progress(at: index) else { return }
        let history = self.history
        let manga = self.manga
        historySaveQueue.sync {
            try? history.save(manga, progress: progress)
        }
    }
}

private struct ReaderPagesRepresentable: UIViewControllerRepresentable {
    let model: ReaderViewModel

    func makeUIViewController(context: Context) -> ReaderViewController {
        let controller = ReaderViewController(session: model.session, mode: model.mode)
        controller.delegate = model
        model.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: ReaderViewController, context: Context) {}
}
