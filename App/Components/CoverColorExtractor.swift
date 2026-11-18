import SwiftUI
import UIKit
import CoreImage
import Nuke
import KomaCore

/// Extracts a deep background tone from a cover image (average color, darkened), cached by URL.
final class CoverColorExtractor: @unchecked Sendable {
    static let shared = CoverColorExtractor()

    /// Shared Core Image context; creating one per extraction is expensive.
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
    /// Covers are downsampled to this pixel size before averaging.
    private static let samplePixels: CGFloat = 64

    private let cache = NSCache<NSString, UIColor>()

    init() {
        cache.countLimit = 200
    }

    /// Returns the cached tone if one was already extracted.
    func cachedColor(for url: URL) -> Color? {
        cache.object(forKey: url.absoluteString as NSString).map { Color(uiColor: $0) }
    }

    /// Loads a small thumbnail of the cover and returns its deepened average color, or nil on failure.
    func color(for url: URL) async -> Color? {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            return Color(uiColor: cached)
        }
        let size = CGSize(width: Self.samplePixels, height: Self.samplePixels)
        let request = ImageRequest(url: url, processors: [.resize(size: size, unit: .pixels)])
        guard let image = try? await ImagePipeline.shared.image(for: request),
              let cgImage = image.cgImage else { return nil }
        if Task.isCancelled { return nil }
        let box = ImageBox(image: cgImage)
        let tone = await Task.detached(priority: .utility) {
            Self.deepTone(of: box.image)
        }.value
        guard let tone else { return nil }
        cache.setObject(tone, forKey: key)
        return Color(uiColor: tone)
    }

    /// CIAreaAverage over the whole image, then clamps HSB to a deep tone. Runs off the main thread.
    private static func deepTone(of cgImage: CGImage) -> UIColor? {
        let input = CIImage(cgImage: cgImage)
        guard !input.extent.isEmpty,
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: input,
                kCIInputExtentKey: CIVector(cgRect: input.extent)
              ]),
              let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB())
        let average = UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return nil }
        let tone = CoverTone.deepened(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness))
        return UIColor(
            hue: CGFloat(tone.hue),
            saturation: CGFloat(tone.saturation),
            brightness: CGFloat(tone.brightness),
            alpha: 1)
    }
}

/// Carries a CGImage into the detached extraction task.
private struct ImageBox: @unchecked Sendable {
    let image: CGImage
}
