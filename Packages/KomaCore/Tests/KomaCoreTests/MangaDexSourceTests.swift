import XCTest
@testable import KomaCore

private final class StubClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: @Sendable (URLRequest) throws -> String

    init(handler: @escaping @Sendable (URLRequest) throws -> String) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        recorded.append(request)
        lock.unlock()
        let body = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

final class MangaDexSourceTests: XCTestCase {
    // MARK: helpers

    private func makeSource(
        settings: NetworkSettings = .default,
        handler: @escaping @Sendable (URLRequest) throws -> String
    ) -> (MangaDexSource, StubClient) {
        let client = StubClient(handler: handler)
        let source = MangaDexSource(client: client, settings: { settings })
        return (source, client)
    }

    private func query(_ request: URLRequest) -> [URLQueryItem] {
        let url = request.url!
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private func values(_ request: URLRequest, _ name: String) -> [String] {
        query(request).filter { $0.name == name }.compactMap { $0.value }
    }

    private func value(_ request: URLRequest, _ name: String) -> String? {
        values(request, name).first
    }

    private func settings(adult: Bool = false, dataSaver: Bool = false, custom: Bool = false) -> NetworkSettings {
        var s = NetworkSettings.default
        s.showAdult = adult
        s.dataSaver = dataSaver
        if custom {
            s.usesCustomUploads = true
            s.uploadsBaseURL = URL(string: "https://img.example.com")!
        }
        return s
    }

    private let emptyList = MangaDexFixtures.list([], total: 0)

    // MARK: list queries

    func testPopularQueryWithoutAdult() async throws {
        let list = emptyList
        let (source, client) = makeSource { _ in list }
        _ = try await source.popular(page: 2)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.host, "api.mangadex.org")
        XCTAssertEqual(request.url?.path, "/manga")
        XCTAssertEqual(values(request, "contentRating[]"), ["safe", "suggestive"])
        XCTAssertEqual(values(request, "availableTranslatedLanguage[]"), ["zh", "zh-hk", "en"])
        XCTAssertEqual(value(request, "offset"), "30")
        XCTAssertEqual(value(request, "limit"), "30")
        XCTAssertEqual(value(request, "order[followedCount]"), "desc")
        XCTAssertEqual(value(request, "hasAvailableChapters"), "true")
        XCTAssertEqual(values(request, "includes[]"), ["cover_art"])
    }

    func testPopularQueryWithAdult() async throws {
        let list = emptyList
        let (source, client) = makeSource(settings: settings(adult: true)) { _ in list }
        _ = try await source.popular(page: 1)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(values(request, "contentRating[]"), ["safe", "suggestive", "erotica", "pornographic"])
        XCTAssertEqual(value(request, "offset"), "0")
    }

    func testLatestUsesLatestUploadedOrder() async throws {
        let list = emptyList
        let (source, client) = makeSource { _ in list }
        _ = try await source.latest(page: 1)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(value(request, "order[latestUploadedChapter]"), "desc")
        XCTAssertNil(value(request, "order[followedCount]"))
    }

    func testSearchAddsTitleAndStatus() async throws {
        let list = emptyList
        let (source, client) = makeSource { _ in list }
        _ = try await source.search(query: "one piece", filters: ["status": "ongoing"], page: 1)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(value(request, "title"), "one piece")
        XCTAssertEqual(values(request, "status[]"), ["ongoing"])
        XCTAssertEqual(value(request, "order[relevance]"), "desc")
        XCTAssertNil(value(request, "order[followedCount]"))
    }

    func testAdultPicksThrowsWhenDisabled() async {
        let list = emptyList
        let (source, client) = makeSource { _ in list }
        do {
            _ = try await source.adultPicks(page: 1)
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? SourceError, .unsupported)
        }
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testAdultPicksQueryOnlyAdultRatings() async throws {
        let list = emptyList
        let (source, client) = makeSource(settings: settings(adult: true)) { _ in list }
        _ = try await source.adultPicks(page: 1)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(values(request, "contentRating[]"), ["erotica", "pornographic"])
        XCTAssertEqual(value(request, "order[followedCount]"), "desc")
    }

    func testFeaturedReturnsFirstEight() async throws {
        let items = (0..<12).map { MangaDexFixtures.manga(id: "m-\($0)") }
        let list = MangaDexFixtures.list(items, total: 12)
        let (source, client) = makeSource { _ in list }
        let featured = try await source.featured()
        XCTAssertEqual(featured.count, 8)
        XCTAssertEqual(featured.first?.id, "m-0")
        XCTAssertEqual(value(try XCTUnwrap(client.requests.first), "offset"), "0")
    }

    func testFeaturedNeverIncludesAdultRatings() async throws {
        let list = MangaDexFixtures.list([MangaDexFixtures.manga()], total: 1)
        let (source, client) = makeSource(settings: settings(adult: true)) { _ in list }
        _ = try await source.featured()
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(values(request, "contentRating[]"), ["safe", "suggestive"])
    }

    func testTransportCancelledMapsToCancellationError() async {
        let (source, _) = makeSource { _ in throw URLError(.cancelled) }
        do {
            _ = try await source.popular(page: 1)
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testDecodesEmptyLocalizedMapsAndNullAttributes() async throws {
        let item = """
        {"id":"r1","type":"manga","attributes":{"title":{"en":"Robust"},"altTitles":[{},{"zh":"稳健"}],"description":[],"status":"ongoing","contentRating":"safe","tags":[{"id":"t","type":"tag","attributes":{"name":[]}}]},"relationships":[{"id":"c","type":"cover_art","attributes":{"fileName":"r.jpg"}},{"id":"a","type":"author","attributes":null}]}
        """
        let list = MangaDexFixtures.list([item], total: 1)
        let detail = MangaDexFixtures.detail(item)
        let (source, _) = makeSource { request in
            request.url?.path == "/manga" ? list : detail
        }
        let page = try await source.popular(page: 1)
        let ref = try XCTUnwrap(page.items.first)
        XCTAssertEqual(ref.title, "稳健")
        XCTAssertEqual(ref.coverURL?.absoluteString, "https://uploads.mangadex.org/covers/r1/r.jpg.512.jpg")
        let details = try await source.details(for: ref)
        XCTAssertNil(details.description)
        XCTAssertTrue(details.tags.isEmpty)
        XCTAssertNil(details.author)
    }

    // MARK: parsing

    func testParsesTitlePreferringChinese() async throws {
        let item = MangaDexFixtures.manga(
            id: "abc",
            titleEn: "Hello World",
            altTitles: ["{\"ja\":\"こんにちは\"}", "{\"zh\":\"你好世界\"}"],
            coverFile: "cover-file.jpg"
        )
        let list = MangaDexFixtures.list([item], total: 1)
        let (source, _) = makeSource { _ in list }
        let page = try await source.popular(page: 1)
        let ref = try XCTUnwrap(page.items.first)
        XCTAssertEqual(ref.title, "你好世界")
        XCTAssertEqual(ref.sourceId, "mangadex")
        XCTAssertEqual(ref.coverURL?.absoluteString, "https://uploads.mangadex.org/covers/abc/cover-file.jpg.512.jpg")
    }

    func testTitleFallsBackToEnglishAndNilCover() async throws {
        let item = MangaDexFixtures.manga(id: "z", titleEn: "Only English", coverFile: nil)
        let list = MangaDexFixtures.list([item], total: 1)
        let (source, _) = makeSource { _ in list }
        let page = try await source.popular(page: 1)
        let ref = try XCTUnwrap(page.items.first)
        XCTAssertEqual(ref.title, "Only English")
        XCTAssertNil(ref.coverURL)
    }

    func testHasNextPage() async throws {
        let page2 = MangaDexFixtures.list([MangaDexFixtures.manga()], limit: 30, offset: 30, total: 61)
        let page3 = MangaDexFixtures.list([MangaDexFixtures.manga()], limit: 30, offset: 60, total: 61)
        let (source, _) = makeSource { request in
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let offset = comps?.queryItems?.first(where: { $0.name == "offset" })?.value
            return offset == "30" ? page2 : page3
        }
        let second = try await source.popular(page: 2)
        XCTAssertTrue(second.hasNextPage)
        let third = try await source.popular(page: 3)
        XCTAssertFalse(third.hasNextPage)
    }

    // MARK: details

    func testDetailsAdds18PlusTag() async throws {
        let item = MangaDexFixtures.manga(
            id: "d1",
            description: "\"en\":\"English desc\"",
            status: "completed",
            contentRating: "erotica",
            tags: [(zh: "动作", en: "Action"), (zh: nil, en: "Romance")],
            author: "Some Author"
        )
        let body = MangaDexFixtures.detail(item)
        let (source, client) = makeSource { _ in body }
        let details = try await source.details(for: MangaRef(sourceId: "mangadex", id: "d1", title: "t"))
        XCTAssertEqual(details.tags, ["动作", "Romance", "18+"])
        XCTAssertEqual(details.status, .completed)
        XCTAssertEqual(details.author, "Some Author")
        XCTAssertEqual(details.description, "English desc")
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.path, "/manga/d1")
        XCTAssertEqual(values(request, "includes[]"), ["author", "cover_art"])
    }

    func testDetailsDescriptionPrefersChineseAndNoAdultTag() async throws {
        let item = MangaDexFixtures.manga(
            id: "d2",
            description: "\"en\":\"English\",\"zh\":\"中文简介\"",
            status: "weird",
            contentRating: "safe"
        )
        let body = MangaDexFixtures.detail(item)
        let (source, _) = makeSource { _ in body }
        let details = try await source.details(for: MangaRef(sourceId: "mangadex", id: "d2", title: "t"))
        XCTAssertEqual(details.description, "中文简介")
        XCTAssertEqual(details.status, .unknown)
        XCTAssertFalse(details.tags.contains("18+"))
    }

    // MARK: chapters

    private func feedSource(_ items: [String], total: Int? = nil) -> (MangaDexSource, StubClient) {
        let body = MangaDexFixtures.list(items, limit: 500, offset: 0, total: total ?? items.count)
        return makeSource { _ in body }
    }

    private let manga = MangaRef(sourceId: "mangadex", id: "m-1", title: "t")

    func testChaptersFeedQuery() async throws {
        let (source, client) = feedSource([MangaDexFixtures.chapter(id: "c1", chapter: "1")])
        _ = try await source.chapters(for: manga)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.path, "/manga/m-1/feed")
        XCTAssertEqual(value(request, "limit"), "500")
        XCTAssertEqual(value(request, "offset"), "0")
        XCTAssertEqual(values(request, "translatedLanguage[]"), ["zh", "zh-hk", "en"])
        XCTAssertEqual(value(request, "order[volume]"), "asc")
        XCTAssertEqual(value(request, "order[chapter]"), "asc")
        XCTAssertEqual(values(request, "includes[]"), ["scanlation_group"])
        XCTAssertEqual(values(request, "contentRating[]"), ["safe", "suggestive", "erotica", "pornographic"])
    }

    func testChaptersDropExternalAndEmpty() async throws {
        let (source, _) = feedSource([
            MangaDexFixtures.chapter(id: "ok", chapter: "1"),
            MangaDexFixtures.chapter(id: "ext", chapter: "2", externalUrl: "https://example.com/read"),
            MangaDexFixtures.chapter(id: "empty", chapter: "3", pages: 0),
        ])
        let chapters = try await source.chapters(for: manga)
        XCTAssertEqual(chapters.map(\.id), ["ok"])
    }

    func testChaptersDedupeByLanguagePriority() async throws {
        let (source, _) = feedSource([
            MangaDexFixtures.chapter(id: "en-5", chapter: "5", lang: "en", publishAt: "2023-01-01T00:00:00+00:00"),
            MangaDexFixtures.chapter(id: "zh-5", chapter: "5", lang: "zh", publishAt: "2024-06-01T00:00:00+00:00"),
        ])
        let chapters = try await source.chapters(for: manga)
        XCTAssertEqual(chapters.map(\.id), ["zh-5"])
    }

    func testChaptersDedupeTieUsesEarliestPublish() async throws {
        let (source, _) = feedSource([
            MangaDexFixtures.chapter(id: "late", chapter: "7", lang: "zh", publishAt: "2024-06-01T00:00:00+00:00"),
            MangaDexFixtures.chapter(id: "early", chapter: "7", lang: "zh", publishAt: "2024-01-01T00:00:00+00:00"),
        ])
        let chapters = try await source.chapters(for: manga)
        XCTAssertEqual(chapters.map(\.id), ["early"])
    }

    func testChaptersKeepOneshots() async throws {
        let (source, _) = feedSource([
            MangaDexFixtures.chapter(id: "os-1", chapter: nil, title: "Special A"),
            MangaDexFixtures.chapter(id: "os-2", chapter: nil, title: "Special B"),
        ])
        let chapters = try await source.chapters(for: manga)
        XCTAssertEqual(Set(chapters.map(\.id)), ["os-1", "os-2"])
        XCTAssertEqual(chapters.count, 2)
    }

    func testChaptersSortedAndIndexed() async throws {
        let (source, _) = feedSource([
            MangaDexFixtures.chapter(id: "c10", chapter: "10", title: "Ten"),
            MangaDexFixtures.chapter(id: "c2", chapter: "2", title: "Two"),
            MangaDexFixtures.chapter(id: "c25", chapter: "2.5"),
            MangaDexFixtures.chapter(id: "cx", chapter: nil),
        ])
        let chapters = try await source.chapters(for: manga)
        XCTAssertEqual(chapters.map(\.id), ["c2", "c25", "c10", "cx"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(chapters.map(\.title), ["第 2 话 · Two", "第 2.5 话", "第 10 话 · Ten", "番外"])
        XCTAssertEqual(chapters.map(\.number), [2, 2.5, 10, nil])
        XCTAssertEqual(chapters.first?.mangaId, "m-1")
        XCTAssertEqual(chapters.first?.sourceId, "mangadex")
    }

    func testChaptersPaginates() async throws {
        let first = MangaDexFixtures.list([MangaDexFixtures.chapter(id: "a", chapter: "1")], limit: 500, offset: 0, total: 600)
        let second = MangaDexFixtures.list([MangaDexFixtures.chapter(id: "b", chapter: "2")], limit: 500, offset: 500, total: 600)
        let (source, client) = makeSource { request in
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let offset = comps?.queryItems?.first(where: { $0.name == "offset" })?.value
            return offset == "0" ? first : second
        }
        let chapters = try await source.chapters(for: manga)
        XCTAssertEqual(chapters.map(\.id), ["a", "b"])
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.requests.compactMap { value($0, "offset") }, ["0", "500"])
    }

    // MARK: pages

    private let chapter = Chapter(id: "ch-1", mangaId: "m-1", sourceId: "mangadex", title: "t", number: 1, index: 0)

    func testPagesDataAndFallback() async throws {
        let body = MangaDexFixtures.atHome()
        let (source, client) = makeSource { _ in body }
        let pages = try await source.pages(for: chapter)
        XCTAssertEqual(client.requests.first?.url?.path, "/at-home/server/ch-1")
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].index, 0)
        XCTAssertEqual(pages[0].url.absoluteString, "https://xyz.mangadex.network/data/h/1.png")
        XCTAssertEqual(pages[0].fallbackURL?.absoluteString, "https://uploads.mangadex.org/data/h/1.png")
        XCTAssertEqual(pages[1].url.absoluteString, "https://xyz.mangadex.network/data/h/2.png")
    }

    func testPagesDataSaver() async throws {
        let body = MangaDexFixtures.atHome()
        let (source, _) = makeSource(settings: settings(dataSaver: true)) { _ in body }
        let pages = try await source.pages(for: chapter)
        XCTAssertEqual(pages[0].url.absoluteString, "https://xyz.mangadex.network/data-saver/h/1.jpg")
        XCTAssertEqual(pages[0].fallbackURL?.absoluteString, "https://uploads.mangadex.org/data-saver/h/1.jpg")
    }

    func testPagesCustomUploads() async throws {
        let body = MangaDexFixtures.atHome()
        let (source, _) = makeSource(settings: settings(custom: true)) { _ in body }
        let pages = try await source.pages(for: chapter)
        XCTAssertEqual(pages[0].url.absoluteString, "https://img.example.com/data/h/1.png")
        XCTAssertNil(pages[0].fallbackURL)
    }

    // MARK: settings

    func testCustomAPIBase() async throws {
        var s = NetworkSettings.default
        s.apiBaseURL = URL(string: "https://md.example.com")!
        let list = emptyList
        let (source, client) = makeSource(settings: s) { _ in list }
        _ = try await source.popular(page: 1)
        XCTAssertEqual(client.requests.first?.url?.host, "md.example.com")
        XCTAssertEqual(client.requests.first?.url?.path, "/manga")
    }

    func testPageRefDecodesLegacyJSONWithoutFallback() throws {
        let json = "{\"index\":0,\"url\":\"https://a.example/1.png\",\"headers\":{}}"
        let ref = try JSONDecoder().decode(PageRef.self, from: Data(json.utf8))
        XCTAssertNil(ref.fallbackURL)
    }
}
