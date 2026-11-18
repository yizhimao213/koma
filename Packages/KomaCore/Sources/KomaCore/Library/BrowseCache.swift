import Foundation

/// Stores the last successfully loaded browse page per source and list kind, so Discover can show it instantly.
public final class BrowseCache: @unchecked Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func store(_ page: MangaPage, sourceId: String, kind: String) {
        guard let data = try? JSONEncoder().encode(page) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(sourceId: sourceId, kind: kind), options: .atomic)
    }

    public func load(sourceId: String, kind: String) -> MangaPage? {
        guard let data = try? Data(contentsOf: fileURL(sourceId: sourceId, kind: kind)) else { return nil }
        return try? JSONDecoder().decode(MangaPage.self, from: data)
    }

    private func fileURL(sourceId: String, kind: String) -> URL {
        let raw = "\(sourceId)_\(kind)"
        var safe = ""
        for scalar in raw.unicodeScalars {
            let isAllowed = (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar))
                || scalar == "_" || scalar == "-"
            safe.unicodeScalars.append(isAllowed ? scalar : "_")
        }
        return directory.appendingPathComponent("\(safe).json")
    }
}
