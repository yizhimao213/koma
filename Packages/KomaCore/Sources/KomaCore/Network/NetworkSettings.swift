import Foundation

public struct NetworkSettings: Sendable, Equatable {
    public var apiBaseURL: URL
    public var uploadsBaseURL: URL
    public var usesCustomUploads: Bool
    public var dataSaver: Bool
    public var languages: [String]
    public var showAdult: Bool

    public init(
        apiBaseURL: URL,
        uploadsBaseURL: URL,
        usesCustomUploads: Bool,
        dataSaver: Bool,
        languages: [String],
        showAdult: Bool
    ) {
        self.apiBaseURL = apiBaseURL
        self.uploadsBaseURL = uploadsBaseURL
        self.usesCustomUploads = usesCustomUploads
        self.dataSaver = dataSaver
        self.languages = languages
        self.showAdult = showAdult
    }

    public static let `default` = NetworkSettings(
        apiBaseURL: URL(string: "https://api.mangadex.org")!,
        uploadsBaseURL: URL(string: "https://uploads.mangadex.org")!,
        usesCustomUploads: false,
        dataSaver: false,
        languages: ["zh", "zh-hk", "en"],
        showAdult: false
    )
}
