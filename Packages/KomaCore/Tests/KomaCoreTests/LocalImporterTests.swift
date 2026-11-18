import XCTest
@testable import KomaCore

final class LocalImporterTests: XCTestCase {
    var work: URL!
    var library: URL!

    override func setUpWithError() throws {
        work = try LocalTestSupport.makeTempDir()
        library = work.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func pageFiles(_ ref: MangaRef, chapter: String = "c0001") -> [String] {
        LocalTestSupport.contents(of: library.appendingPathComponent(ref.id).appendingPathComponent(chapter))
    }

    func testImportCBZ() throws {
        let zip = work.appendingPathComponent("Book.cbz")
        try LocalTestSupport.makeZip(at: zip, entries: [
            ("2.jpg", LocalTestSupport.fakeImage("2")),
            ("10.jpg", LocalTestSupport.fakeImage("10")),
            ("1.jpg", LocalTestSupport.fakeImage("1"))
        ])
        let ref = try LocalImporter(libraryRoot: library).importItem(at: zip)
        XCTAssertEqual(ref.title, "Book")
        XCTAssertEqual(ref.sourceId, "local")
        XCTAssertEqual(ref.id.count, 16)
        XCTAssertEqual(pageFiles(ref), ["0001.jpg", "0002.jpg", "0003.jpg"])
        let first = library.appendingPathComponent(ref.id).appendingPathComponent("c0001/0001.jpg")
        XCTAssertEqual(try Data(contentsOf: first), LocalTestSupport.fakeImage("1"))
        let third = library.appendingPathComponent(ref.id).appendingPathComponent("c0001/0003.jpg")
        XCTAssertEqual(try Data(contentsOf: third), LocalTestSupport.fakeImage("10"))
        XCTAssertNotNil(ref.coverURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ref.coverURL!.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: library.appendingPathComponent(ref.id).appendingPathComponent("manga.json").path))
    }

    func testImportSkipsJunk() throws {
        let zip = work.appendingPathComponent("Junk.zip")
        try LocalTestSupport.makeZip(at: zip, entries: [
            ("__MACOSX/._1.jpg", LocalTestSupport.fakeImage("junk")),
            (".DS_Store", LocalTestSupport.fakeImage("ds")),
            ("info.txt", LocalTestSupport.fakeImage("txt")),
            ("sub/1.png", LocalTestSupport.fakeImage("1")),
            ("sub/2.png", LocalTestSupport.fakeImage("2"))
        ])
        let ref = try LocalImporter(libraryRoot: library).importItem(at: zip)
        XCTAssertEqual(pageFiles(ref), ["0001.png", "0002.png"])
    }

    func testImportEmptyArchiveThrows() throws {
        let zip = work.appendingPathComponent("Empty.cbz")
        try LocalTestSupport.makeZip(at: zip, entries: [("readme.txt", LocalTestSupport.fakeImage("r"))])
        XCTAssertThrowsError(try LocalImporter(libraryRoot: library).importItem(at: zip)) { error in
            XCTAssertEqual(error as? LocalImportError, .noImages)
        }
        XCTAssertEqual(LocalTestSupport.contents(of: library), [])
    }

    func testImportCorruptArchiveThrows() throws {
        let bad = work.appendingPathComponent("x.cbz")
        try Data((0..<2048).map { _ in UInt8.random(in: 0...255) }).write(to: bad)
        XCTAssertThrowsError(try LocalImporter(libraryRoot: library).importItem(at: bad))
        XCTAssertEqual(LocalTestSupport.contents(of: library), [])
    }

    func testImportFolderOfArchives() throws {
        let folder = work.appendingPathComponent("MyManga", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try LocalTestSupport.makeZip(at: folder.appendingPathComponent("第10话.cbz"), entries: [
            ("1.jpg", LocalTestSupport.fakeImage("a"))
        ])
        try LocalTestSupport.makeZip(at: folder.appendingPathComponent("第2话.cbz"), entries: [
            ("1.jpg", LocalTestSupport.fakeImage("b")),
            ("2.jpg", LocalTestSupport.fakeImage("c"))
        ])
        let ref = try LocalImporter(libraryRoot: library).importItem(at: folder)
        XCTAssertEqual(ref.title, "MyManga")
        let json = try Data(contentsOf: library.appendingPathComponent(ref.id).appendingPathComponent("manga.json"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let chapters = try XCTUnwrap(obj["chapters"] as? [[String: Any]])
        XCTAssertEqual(chapters.compactMap { $0["title"] as? String }, ["第2话", "第10话"])
        XCTAssertEqual(pageFiles(ref, chapter: "c0001").count, 2)
        XCTAssertEqual(pageFiles(ref, chapter: "c0002").count, 1)
    }

    func testImportImageFolder() throws {
        let folder = work.appendingPathComponent("Pics", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try LocalTestSupport.fakeImage("1").write(to: folder.appendingPathComponent("01.PNG"))
        try LocalTestSupport.fakeImage("2").write(to: folder.appendingPathComponent("02.PNG"))
        let ref = try LocalImporter(libraryRoot: library).importItem(at: folder)
        XCTAssertEqual(pageFiles(ref), ["0001.png", "0002.png"])
    }

    func testImportTwiceThrowsAlreadyImported() throws {
        let zip = work.appendingPathComponent("Twice.cbz")
        try LocalTestSupport.makeZip(at: zip, entries: [("1.jpg", LocalTestSupport.fakeImage("1"))])
        let importer = LocalImporter(libraryRoot: library)
        _ = try importer.importItem(at: zip)
        XCTAssertThrowsError(try importer.importItem(at: zip)) { error in
            XCTAssertEqual(error as? LocalImportError, .alreadyImported("Twice"))
        }
    }

    func testDecodeGBKName() {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let raw = "第1话/01.jpg".data(using: gb)!
        XCTAssertEqual(decodeZipEntryName(raw, isUTF8Flag: false), "第1话/01.jpg")
    }

    func testDecodeUTF8Name() {
        let raw = Data("第1话/01.jpg".utf8)
        XCTAssertEqual(decodeZipEntryName(raw, isUTF8Flag: true), "第1话/01.jpg")
        XCTAssertEqual(decodeZipEntryName(raw, isUTF8Flag: false), "第1话/01.jpg")
    }

    func testImportGBKEncodedArchiveOrdersChaptersNaturally() throws {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let zip = work.appendingPathComponent("GBK.cbz")
        try LocalTestSupport.makeRawNameZip(at: zip, entries: [
            (name: "第10话/01.jpg".data(using: gb)!, data: LocalTestSupport.fakeImage("ten")),
            (name: "第2话/01.jpg".data(using: gb)!, data: LocalTestSupport.fakeImage("two"))
        ])
        let ref = try LocalImporter(libraryRoot: library).importItem(at: zip)
        XCTAssertEqual(pageFiles(ref), ["0001.jpg", "0002.jpg"])
        let dir = library.appendingPathComponent(ref.id).appendingPathComponent("c0001")
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("0001.jpg")), LocalTestSupport.fakeImage("two"))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("0002.jpg")), LocalTestSupport.fakeImage("ten"))
    }
}
