import Foundation

public final class SourceRegistry {
    private let sources: [any MangaSource]

    public init(sources: [any MangaSource]) {
        self.sources = sources
    }

    public func source(id: String) -> (any MangaSource)? {
        sources.first { $0.id == id }
    }

    /// All registered sources, in the order given at init.
    public var all: [any MangaSource] { sources }
}
