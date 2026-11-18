import Foundation

enum MangaDexFixtures {
    static func manga(
        id: String = "m-1",
        titleEn: String = "English Title",
        altTitles: [String] = [],
        description: String? = nil,
        status: String = "ongoing",
        contentRating: String = "safe",
        tags: [(zh: String?, en: String)] = [],
        coverFile: String? = "cover.jpg",
        author: String? = nil
    ) -> String {
        let alt = altTitles.joined(separator: ",")
        let desc = description.map { "{\($0)}" } ?? "{}"
        let tagJSON = tags.map { tag -> String in
            var names = "\"en\":\"\(tag.en)\""
            if let zh = tag.zh { names += ",\"zh\":\"\(zh)\"" }
            return "{\"id\":\"t-\(tag.en)\",\"type\":\"tag\",\"attributes\":{\"name\":{\(names)}}}"
        }.joined(separator: ",")
        var rels: [String] = []
        if let coverFile {
            rels.append("{\"id\":\"c-1\",\"type\":\"cover_art\",\"attributes\":{\"fileName\":\"\(coverFile)\"}}")
        }
        if let author {
            rels.append("{\"id\":\"a-1\",\"type\":\"author\",\"attributes\":{\"name\":\"\(author)\"}}")
        }
        rels.append("{\"id\":\"x-1\",\"type\":\"artist\"}")
        return """
        {"id":"\(id)","type":"manga","attributes":{"title":{"en":"\(titleEn)"},"altTitles":[\(alt)],"description":\(desc),"status":"\(status)","contentRating":"\(contentRating)","tags":[\(tagJSON)],"unknownField":123},"relationships":[\(rels.joined(separator: ","))]}
        """
    }

    static func list(_ items: [String], limit: Int = 30, offset: Int = 0, total: Int) -> String {
        """
        {"result":"ok","response":"collection","data":[\(items.joined(separator: ","))],"limit":\(limit),"offset":\(offset),"total":\(total)}
        """
    }

    static func detail(_ item: String) -> String {
        "{\"result\":\"ok\",\"response\":\"entity\",\"data\":\(item)}"
    }

    static func chapter(
        id: String,
        chapter: String?,
        title: String? = nil,
        lang: String = "zh",
        externalUrl: String? = nil,
        pages: Int = 20,
        publishAt: String = "2024-01-01T00:00:00+00:00"
    ) -> String {
        let chapterJSON = chapter.map { "\"\($0)\"" } ?? "null"
        let titleJSON = title.map { "\"\($0)\"" } ?? "null"
        let external = externalUrl.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(id)","type":"chapter","attributes":{"chapter":\(chapterJSON),"title":\(titleJSON),"translatedLanguage":"\(lang)","externalUrl":\(external),"pages":\(pages),"publishAt":"\(publishAt)"},"relationships":[{"id":"g-1","type":"scanlation_group"}]}
        """
    }

    static func atHome(baseUrl: String = "https://xyz.mangadex.network", hash: String = "h", data: [String] = ["1.png", "2.png"], dataSaver: [String] = ["1.jpg", "2.jpg"]) -> String {
        let d = data.map { "\"\($0)\"" }.joined(separator: ",")
        let s = dataSaver.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"result\":\"ok\",\"baseUrl\":\"\(baseUrl)\",\"chapter\":{\"hash\":\"\(hash)\",\"data\":[\(d)],\"dataSaver\":[\(s)]}}"
    }
}
