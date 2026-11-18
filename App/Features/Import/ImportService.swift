import Foundation
import KomaCore

final class ImportService: @unchecked Sendable {
    private let libraryRoot: URL
    private let library: LibraryRepository

    init(libraryRoot: URL, library: LibraryRepository) {
        self.libraryRoot = libraryRoot
        self.library = library
    }

    /// Imports each URL sequentially (security-scoped access, PDFs rendered to JPEG first).
    func importFiles(_ urls: [URL]) async -> [Result<MangaRef, Error>] {
        var results: [Result<MangaRef, Error>] = []
        for url in urls {
            let outcome = await Task.detached(priority: .userInitiated) { [self] () -> Result<MangaRef, Error> in
                do {
                    return .success(try await importOne(url))
                } catch {
                    return .failure(error)
                }
            }.value
            results.append(outcome)
        }
        return results
    }

    private func importOne(_ url: URL) async throws -> MangaRef {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        var importURL = url
        var tempRoot: URL?
        defer { if let tempRoot { try? fm.removeItem(at: tempRoot) } }

        if url.pathExtension.lowercased() == "pdf" {
            let root = fm.temporaryDirectory.appendingPathComponent("koma-pdf-\(UUID().uuidString)", isDirectory: true)
            tempRoot = root
            let folder = root.appendingPathComponent(url.deletingPathExtension().lastPathComponent, isDirectory: true)
            try PDFPageRenderer.render(pdf: url, to: folder, maxPixelWidth: 2048)
            importURL = folder
        }

        let ref = try LocalImporter(libraryRoot: libraryRoot).importItem(at: importURL)
        let source = LocalSource(libraryRoot: libraryRoot)
        let details = try await source.details(for: ref)
        let chapters = try await source.chapters(for: ref)
        try library.upsert(details: details, chapters: chapters)
        try library.setInLibrary(details.ref, true)
        return details.ref
    }

    static func message(for error: Error) -> String {
        switch error {
        case LocalImportError.noImages:
            return "导入失败：没有找到图片"
        case LocalImportError.alreadyImported(let title):
            return "已经导入过《\(title)》"
        case LocalImportError.unsupportedType:
            return "导入失败：不支持的文件类型"
        default:
            return "导入失败"
        }
    }
}
