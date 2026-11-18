import UIKit
import KomaCore

enum PDFPageRenderer {
    /// Renders every page of `pdf` into `folder` as 0001.jpg, 0002.jpg, ... (JPEG quality 0.85).
    /// Returns the number of pages written.
    @discardableResult
    static func render(pdf: URL, to folder: URL, maxPixelWidth: CGFloat = 2048) throws -> Int {
        guard let document = CGPDFDocument(pdf as CFURL) else {
            throw LocalImportError.unsupportedType(pdf.lastPathComponent)
        }
        if document.isEncrypted && !document.unlockWithPassword("") {
            throw LocalImportError.unsupportedType(pdf.lastPathComponent)
        }
        guard document.numberOfPages > 0 else { throw LocalImportError.noImages }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var written = 0
        for pageNumber in 1...document.numberOfPages {
            guard let page = document.page(at: pageNumber) else { continue }
            try autoreleasepool {
                let box = page.getBoxRect(.mediaBox)
                let rotated = page.rotationAngle % 180 != 0
                let pageSize = rotated ? CGSize(width: box.height, height: box.width) : box.size
                guard pageSize.width > 0, pageSize.height > 0 else { return }

                let scale = maxPixelWidth / pageSize.width
                let target = CGSize(width: maxPixelWidth, height: (pageSize.height * scale).rounded())
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let image = UIGraphicsImageRenderer(size: target, format: format).image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: target))
                    let cg = ctx.cgContext
                    cg.translateBy(x: 0, y: target.height)
                    cg.scaleBy(x: 1, y: -1)
                    cg.concatenate(page.getDrawingTransform(
                        .mediaBox, rect: CGRect(origin: .zero, size: target), rotate: 0, preserveAspectRatio: true))
                    cg.drawPDFPage(page)
                }
                guard let data = image.jpegData(compressionQuality: 0.85) else { return }
                written += 1
                try data.write(to: folder.appendingPathComponent(String(format: "%04d.jpg", written)))
            }
        }
        guard written > 0 else { throw LocalImportError.noImages }
        return written
    }
}
