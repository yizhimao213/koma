import Foundation
import Nuke
import KomaCore

enum ImagePipelineConfig {
    /// Installs the shared pipeline used by the reader and covers. Call once at launch.
    static func configure() {
        var configuration = ImagePipeline.Configuration()
        if let dataCache = try? DataCache(name: "com.koma.reader.images") {
            dataCache.sizeLimit = AppSettings.storedCacheLimitMB() * 1024 * 1024
            configuration.dataCache = dataCache
        }
        configuration.isProgressiveDecodingEnabled = false
        // Decoding, decompression and resizing run on the pipeline's background operation queues
        // (Nuke's defaults); completions are delivered on the main queue.
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
    }
}

/// Builds the image requests for reader pages. Cells and the prefetcher must use the same
/// factory so prefetched images hit the memory cache.
enum PageImageRequest {
    /// - Parameter viewSize: the reader viewport in points; paged images are downsampled to 2x it, webtoon to its width.
    static func make(for page: PageRef, mode: ReadingMode, viewSize: CGSize, priority: ImageRequest.Priority = .normal) -> ImageRequest {
        let processor: any ImageProcessing
        if mode == .webtoon {
            // Strips are much taller than the screen: fit the width only.
            processor = ImageProcessors.Resize(width: viewSize.width, unit: .points, upscale: false)
        } else {
            // 2x the viewport: the paged cell allows pinch zoom, so keep headroom for sharpness.
            let zoomSize = CGSize(width: viewSize.width * 2, height: viewSize.height * 2)
            processor = ImageProcessors.Resize(size: zoomSize, unit: .points, contentMode: .aspectFit, upscale: false)
        }
        if page.headers.isEmpty {
            return ImageRequest(url: page.url, processors: [processor], priority: priority)
        }
        var urlRequest = URLRequest(url: page.url)
        for (field, value) in page.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        return ImageRequest(urlRequest: urlRequest, processors: [processor], priority: priority)
    }
}
