import Foundation
import CryptoKit
import ZIPFoundation

public enum LocalImportError: Error, Equatable {
    case noImages
    case unsupportedType(String)
    case alreadyImported(String)
}

/// On-disk description of an imported manga (`<mangaId>/manga.json`).
struct LocalMangaMeta: Codable {
    struct ChapterMeta: Codable {
        var id: String
        var title: String
    }

    var title: String
    var chapters: [ChapterMeta]
    var importedFrom: String
    var importedAt: Date?

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

let localImageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "avif"]

public struct LocalImporter {
    public let libraryRoot: URL

    public init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot
    }

    private struct ChapterSource {
        var title: String
        var kind: Kind
        enum Kind {
            case archive(URL)
            case images([URL])
        }
    }

    public func importItem(at url: URL) throws -> MangaRef {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw LocalImportError.unsupportedType(url.lastPathComponent)
        }

        let originalName = url.lastPathComponent
        let title: String
        let size: Int64
        let chapterSources: [ChapterSource]

        if isDir.boolValue {
            title = originalName
            size = Self.folderSize(url)
            chapterSources = try Self.chapterSources(forFolder: url)
        } else {
            let ext = url.pathExtension.lowercased()
            guard ext == "cbz" || ext == "zip" else {
                throw LocalImportError.unsupportedType(ext.isEmpty ? originalName : ext)
            }
            title = url.deletingPathExtension().lastPathComponent
            let attrs = try fm.attributesOfItem(atPath: url.path)
            size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            chapterSources = [ChapterSource(title: title, kind: .archive(url))]
        }

        let mangaId = Self.makeId(name: originalName, size: size)
        let finalDir = libraryRoot.appendingPathComponent(mangaId, isDirectory: true)
        if fm.fileExists(atPath: finalDir.path) {
            throw LocalImportError.alreadyImported(title)
        }

        let tempRoot = fm.temporaryDirectory
            .appendingPathComponent("koma-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        var chapterMetas: [LocalMangaMeta.ChapterMeta] = []
        for source in chapterSources {
            let chapterId = String(format: "c%04d", chapterMetas.count + 1)
            let chapterDir = tempRoot.appendingPathComponent(chapterId, isDirectory: true)
            try fm.createDirectory(at: chapterDir, withIntermediateDirectories: true)
            let count: Int
            switch source.kind {
            case .archive(let archiveURL):
                count = try Self.extractImages(fromArchive: archiveURL, to: chapterDir)
            case .images(let files):
                count = try Self.copyImages(files, to: chapterDir)
            }
            if count == 0 {
                // Chapter without images: drop it (a lone chapter ends up as .noImages below).
                try? fm.removeItem(at: chapterDir)
                continue
            }
            chapterMetas.append(.init(id: chapterId, title: source.title))
        }

        guard !chapterMetas.isEmpty else {
            throw LocalImportError.noImages
        }

        let meta = LocalMangaMeta(
            title: title,
            chapters: chapterMetas,
            importedFrom: originalName,
            importedAt: Date()
        )
        try LocalMangaMeta.makeEncoder().encode(meta)
            .write(to: tempRoot.appendingPathComponent("manga.json"), options: .atomic)

        try fm.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try fm.moveItem(at: tempRoot, to: finalDir)

        let cover = Self.firstPage(in: finalDir.appendingPathComponent(chapterMetas[0].id, isDirectory: true))
        return MangaRef(sourceId: "local", id: mangaId, title: title, coverURL: cover)
    }

    // MARK: - Helpers

    static func makeId(name: String, size: Int64) -> String {
        let digest = SHA256.hash(data: Data("\(name)|\(size)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
    }

    static func firstPage(in chapterDir: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: chapterDir.path)) ?? []
        guard let first = names.sorted().first else { return nil }
        return chapterDir.appendingPathComponent(first)
    }

    private static func isJunkComponent(_ component: String) -> Bool {
        component.hasPrefix(".") || component == "__MACOSX"
    }

    private static func isImage(_ name: String) -> Bool {
        localImageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func folderSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else { return 0 }
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    private static func visibleChildren(of folder: URL) throws -> [URL] {
        let children = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        return children.filter { !isJunkComponent($0.lastPathComponent) }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// All image files under `folder` (recursive), junk skipped, naturally ordered.
    private static func imageFiles(under folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let file as URL in enumerator {
            if file.pathComponents.contains("__MACOSX") { continue }
            if isDirectory(file) { continue }
            if isImage(file.lastPathComponent) { files.append(file) }
        }
        return files.sorted { $0.path.naturalCompare($1.path) == .orderedAscending }
    }

    private static func chapterSources(forFolder folder: URL) throws -> [ChapterSource] {
        let children = try visibleChildren(of: folder)
        let directImages = children.filter { !isDirectory($0) && isImage($0.lastPathComponent) }
        if !directImages.isEmpty {
            // Folder of images: one chapter holding every image beneath it.
            return [ChapterSource(title: folder.lastPathComponent, kind: .images(imageFiles(under: folder)))]
        }

        let sorted = children.sorted {
            $0.lastPathComponent.naturalCompare($1.lastPathComponent) == .orderedAscending
        }
        var result: [ChapterSource] = []
        for child in sorted {
            if isDirectory(child) {
                result.append(ChapterSource(
                    title: child.lastPathComponent,
                    kind: .images(imageFiles(under: child))
                ))
            } else {
                let ext = child.pathExtension.lowercased()
                if ext == "cbz" || ext == "zip" {
                    result.append(ChapterSource(
                        title: child.deletingPathExtension().lastPathComponent,
                        kind: .archive(child)
                    ))
                }
            }
        }
        return result
    }

    private static func copyImages(_ files: [URL], to dir: URL) throws -> Int {
        var index = 0
        for file in files {
            index += 1
            let ext = file.pathExtension.lowercased()
            let name = String(format: "%04d", index) + "." + ext
            try FileManager.default.copyItem(at: file, to: dir.appendingPathComponent(name))
        }
        return index
    }

    /// Extracts image entries in natural path order as 0001.ext, 0002.ext, ...
    private static func extractImages(fromArchive url: URL, to dir: URL) throws -> Int {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw LocalImportError.unsupportedType(url.lastPathComponent)
        }

        var candidates: [(name: String, entry: Entry)] = []
        for entry in archive {
            guard entry.type == .file else { continue }
            let name = entry.decodedName.replacingOccurrences(of: "\\", with: "/")
            let components = name.split(separator: "/").map(String.init)
            if components.contains(where: { isJunkComponent($0) }) { continue }
            guard let last = components.last, isImage(last) else { continue }
            candidates.append((name, entry))
        }
        candidates.sort { $0.name.naturalCompare($1.name) == .orderedAscending }

        var index = 0
        for candidate in candidates {
            index += 1
            let ext = (candidate.name as NSString).pathExtension.lowercased()
            let target = dir.appendingPathComponent(String(format: "%04d", index) + "." + ext)
            _ = try archive.extract(candidate.entry, to: target)
        }
        return index
    }
}
