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
        let archive = try Archive(url: url, accessMode: .create)
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

    /// Writes a minimal stored (uncompressed) zip with raw entry-name bytes and general purpose
    /// flag 0 (bit 11 cleared), as legacy Windows zippers produce for GBK names.
    static func makeRawNameZip(at url: URL, entries: [(name: Data, data: Data)]) throws {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) } }
        func crc32(_ data: Data) -> UInt32 {
            var crc: UInt32 = 0xffff_ffff
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 }
            }
            return ~crc
        }
        var body = Data()
        var central = Data()
        for entry in entries {
            let offset = UInt32(body.count)
            let crc: UInt32 = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let nameLength: Int = entry.name.count

            var local = [UInt8]()
            local.append(contentsOf: le32(0x0403_4b50))
            local.append(contentsOf: le16(20))
            local.append(contentsOf: le16(0))
            local.append(contentsOf: le16(0))
            local.append(contentsOf: le16(0))
            local.append(contentsOf: le16(0x21))
            local.append(contentsOf: le32(crc))
            local.append(contentsOf: le32(size))
            local.append(contentsOf: le32(size))
            local.append(contentsOf: le16(nameLength))
            local.append(contentsOf: le16(0))
            body.append(contentsOf: local)
            body.append(entry.name)
            body.append(entry.data)

            var header = [UInt8]()
            header.append(contentsOf: le32(0x0201_4b50))
            header.append(contentsOf: le16(20))
            header.append(contentsOf: le16(20))
            header.append(contentsOf: le16(0))
            header.append(contentsOf: le16(0))
            header.append(contentsOf: le16(0))
            header.append(contentsOf: le16(0x21))
            header.append(contentsOf: le32(crc))
            header.append(contentsOf: le32(size))
            header.append(contentsOf: le32(size))
            header.append(contentsOf: le16(nameLength))
            header.append(contentsOf: le16(0))
            header.append(contentsOf: le16(0))
            header.append(contentsOf: le16(0))
            header.append(contentsOf: le16(0))
            header.append(contentsOf: le32(0))
            header.append(contentsOf: le32(offset))
            central.append(contentsOf: header)
            central.append(entry.name)
        }
        var out = body
        let centralOffset = UInt32(out.count)
        let count: Int = entries.count
        out.append(central)
        var end = [UInt8]()
        end.append(contentsOf: le32(0x0605_4b50))
        end.append(contentsOf: le16(0))
        end.append(contentsOf: le16(0))
        end.append(contentsOf: le16(count))
        end.append(contentsOf: le16(count))
        end.append(contentsOf: le32(UInt32(central.count)))
        end.append(contentsOf: le32(centralOffset))
        end.append(contentsOf: le16(0))
        out.append(contentsOf: end)
        try out.write(to: url)
    }
}
