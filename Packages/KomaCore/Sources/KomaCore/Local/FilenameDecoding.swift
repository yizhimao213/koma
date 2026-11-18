import Foundation
import ZIPFoundation

/// Decodes a raw ZIP entry name. UTF-8 when flagged or when the bytes are valid UTF-8;
/// otherwise GB18030 (superset of GBK), then CP437 as the last resort.
public func decodeZipEntryName(_ raw: Data, isUTF8Flag: Bool) -> String {
    if isUTF8Flag, let s = String(data: raw, encoding: .utf8) {
        return s
    }
    if let s = String(data: raw, encoding: .utf8) {
        return s
    }
    let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    if let s = String(data: raw, encoding: gb18030) {
        return s
    }
    let cp437 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))
    if let s = String(data: raw, encoding: cp437) {
        return s
    }
    return String(decoding: raw, as: UTF8.self)
}

extension Entry {
    /// Recovers the raw file-name bytes of the entry (ZIPFoundation 0.9.x exposes no raw accessor)
    /// by decoding as ISO Latin-1, which maps every byte to exactly one character, then re-encoding.
    /// The UTF-8 general purpose flag is not public, so it is inferred from byte validity
    /// inside `decodeZipEntryName`.
    var decodedName: String {
        let latin1 = path(using: .isoLatin1)
        let raw = latin1.data(using: .isoLatin1) ?? Data(path.utf8)
        return decodeZipEntryName(raw, isUTF8Flag: false)
    }
}
