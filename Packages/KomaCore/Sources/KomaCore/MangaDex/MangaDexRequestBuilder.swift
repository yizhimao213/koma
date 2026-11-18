import Foundation

enum MangaDexOrder {
    case followedCount
    case latestUploadedChapter
    case relevance
}

struct MangaDexRequestBuilder {
    static let pageSize = 30
    static let feedPageSize = 500
    static let safeRatings = ["safe", "suggestive"]
    static let adultRatings = ["erotica", "pornographic"]

    let settings: NetworkSettings

    /// Content ratings allowed for general browsing.
    var browseRatings: [String] {
        settings.showAdult ? Self.safeRatings + Self.adultRatings : Self.safeRatings
    }

    func mangaList(
        page: Int,
        order: MangaDexOrder,
        ratings: [String],
        title: String? = nil,
        status: String? = nil
    ) -> URLRequest {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            URLQueryItem(name: "offset", value: String((max(page, 1) - 1) * Self.pageSize)),
            URLQueryItem(name: "includes[]", value: "cover_art"),
        ]
        switch order {
        case .followedCount:
            items.append(URLQueryItem(name: "order[followedCount]", value: "desc"))
        case .latestUploadedChapter:
            items.append(URLQueryItem(name: "order[latestUploadedChapter]", value: "desc"))
        case .relevance:
            items.append(URLQueryItem(name: "order[relevance]", value: "desc"))
        }
        items.append(URLQueryItem(name: "hasAvailableChapters", value: "true"))
        for language in settings.languages {
            items.append(URLQueryItem(name: "availableTranslatedLanguage[]", value: language))
        }
        for rating in ratings {
            items.append(URLQueryItem(name: "contentRating[]", value: rating))
        }
        if let title, !title.isEmpty {
            items.append(URLQueryItem(name: "title", value: title))
        }
        if let status, !status.isEmpty {
            items.append(URLQueryItem(name: "status[]", value: status))
        }
        return request(path: "manga", items: items)
    }

    func details(id: String) -> URLRequest {
        request(path: "manga/\(id)", items: [
            URLQueryItem(name: "includes[]", value: "author"),
            URLQueryItem(name: "includes[]", value: "cover_art"),
        ])
    }

    func feed(id: String, offset: Int) -> URLRequest {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(Self.feedPageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        for language in settings.languages {
            items.append(URLQueryItem(name: "translatedLanguage[]", value: language))
        }
        items.append(URLQueryItem(name: "order[volume]", value: "asc"))
        items.append(URLQueryItem(name: "order[chapter]", value: "asc"))
        items.append(URLQueryItem(name: "includes[]", value: "scanlation_group"))
        for rating in Self.safeRatings + Self.adultRatings {
            items.append(URLQueryItem(name: "contentRating[]", value: rating))
        }
        return request(path: "manga/\(id)/feed", items: items)
    }

    func atHome(chapterId: String) -> URLRequest {
        request(path: "at-home/server/\(chapterId)", items: [])
    }

    func coverURL(mangaId: String, fileName: String) -> URL? {
        URL(string: "\(Self.trimmed(settings.uploadsBaseURL))/covers/\(mangaId)/\(fileName).512.jpg")
    }

    func pageURL(host: String, segment: String, hash: String, file: String) -> URL? {
        URL(string: "\(host)/\(segment)/\(hash)/\(file)")
    }

    static func trimmed(_ url: URL) -> String {
        var s = url.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func request(path: String, items: [URLQueryItem]) -> URLRequest {
        let base = Self.trimmed(settings.apiBaseURL)
        var components = URLComponents(string: "\(base)/\(path)") ?? URLComponents()
        if !items.isEmpty {
            components.queryItems = items
        }
        let url = components.url ?? settings.apiBaseURL
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }
}
