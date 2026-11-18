import Foundation

/// A MangaDex localized string map (`{"en": "...", "zh": "..."}`). Tolerates `[]` (empty PHP array) and other shapes.
struct MDLocalized: Decodable {
    var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: String].self) {
            values = dict
        } else {
            values = [:]
        }
    }
}

struct MDList<Item: Decodable>: Decodable {
    var data: [Item]
    var limit: Int?
    var offset: Int?
    var total: Int?
}

struct MDEntity<Item: Decodable>: Decodable {
    var data: Item
}

struct MDRelationshipAttributes: Decodable {
    var fileName: String?
    var name: String?
}

struct MDRelationship: Decodable {
    var id: String
    var type: String
    var attributes: MDRelationshipAttributes?

    private enum CodingKeys: String, CodingKey { case id, type, attributes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        attributes = try? c.decodeIfPresent(MDRelationshipAttributes.self, forKey: .attributes)
    }
}

struct MDTagAttributes: Decodable {
    var name: MDLocalized?
}

struct MDTag: Decodable {
    var id: String?
    var attributes: MDTagAttributes?
}

struct MDMangaAttributes: Decodable {
    var title: MDLocalized?
    var altTitles: [MDLocalized]?
    var description: MDLocalized?
    var status: String?
    var contentRating: String?
    var tags: [MDTag]?
}

struct MDManga: Decodable {
    var id: String
    var attributes: MDMangaAttributes
    var relationships: [MDRelationship]?
}

struct MDChapterAttributes: Decodable {
    var chapter: String?
    var title: String?
    var translatedLanguage: String?
    var externalUrl: String?
    var pages: Int?
    var publishAt: String?
}

struct MDChapter: Decodable {
    var id: String
    var attributes: MDChapterAttributes
}

struct MDAtHome: Decodable {
    struct ChapterFiles: Decodable {
        var hash: String
        var data: [String]
        var dataSaver: [String]
    }

    var baseUrl: String
    var chapter: ChapterFiles
}
