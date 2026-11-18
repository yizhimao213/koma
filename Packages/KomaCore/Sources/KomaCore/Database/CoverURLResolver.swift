import Foundation

/// Keeps absolute app-container paths out of the database.
/// Covers that live under the local library root are stored as `local-library:/<relative path>`
/// and resolved against the current library root when read back.
public struct CoverURLResolver: Sendable {
    static let marker = "local-library:/"

    public let libraryRoot: URL?

    public init(libraryRoot: URL? = nil) {
        self.libraryRoot = libraryRoot
    }

    /// String to persist for a cover URL.
    public func storedString(for url: URL?) -> String? {
        guard let url else { return nil }
        if url.isFileURL, let root = libraryRoot {
            let rootPath = root.standardizedFileURL.path
            let path = url.standardizedFileURL.path
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if path.hasPrefix(prefix) {
                return Self.marker + String(path.dropFirst(prefix.count))
            }
        }
        return url.absoluteString
    }

    /// URL for a persisted cover string, relative markers resolved against the current root.
    public func resolve(stored: String?) -> URL? {
        guard let stored else { return nil }
        if stored.hasPrefix(Self.marker) {
            guard let root = libraryRoot else { return nil }
            let relative = String(stored.dropFirst(Self.marker.count))
            return root.appendingPathComponent(relative)
        }
        return URL(string: stored)
    }
}
