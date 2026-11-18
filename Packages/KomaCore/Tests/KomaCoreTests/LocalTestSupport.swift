import Foundation
import ZIPFoundation

enum LocalTestSupport {
    static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("koma-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Builds a zip at `url` containing the given (path, bytes) entries.
    static func makeZip(at url: URL, entries: [(String, Data)]) throws {
        guard let archive = try? Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "LocalTestSupport", code: 1)
        }
        for (path, data) in entries {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                provider: { position, size in
                    data.subdata(in: Int(position)..<(Int(position) + size))
                }
            )
        }
    }

    static func fakeImage(_ tag: String) -> Data {
        Data("fake-image-\(tag)".utf8)
    }

    static func contents(of url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }
}
