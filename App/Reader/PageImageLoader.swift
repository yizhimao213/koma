import UIKit
import Nuke

/// Loads one page image for a cell: memory-cache hits are delivered synchronously (no fade, no flash),
/// everything else is decoded off the main thread by Nuke and delivered on the main queue.
@MainActor
final class PageImageLoader {
    private var task: ImageTask?
    private var generation = 0

    /// - Parameter completion: called with the image (or nil on failure) and whether it came from the memory cache.
    func load(_ request: ImageRequest, completion: @escaping (UIImage?, Bool) -> Void) {
        cancel()
        if let cached = ImagePipeline.shared.cache[request] {
            completion(cached.image, true)
            return
        }
        generation += 1
        let expected = generation
        task = ImagePipeline.shared.loadImage(with: request) { [weak self] result in
            guard let self, self.generation == expected else { return }
            self.task = nil
            switch result {
            case .success(let response):
                completion(response.image, false)
            case .failure:
                completion(nil, false)
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }
}

/// Spinner that only shows up when loading takes noticeably long, so fast loads never flash it.
final class DelayedSpinner: UIActivityIndicatorView {
    init() {
        super.init(style: .medium)
        color = UIColor(white: 1, alpha: 0.5)
        hidesWhenStopped = false
        alpha = 0
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAfterDelay() {
        layer.removeAllAnimations()
        alpha = 0
        startAnimating()
        UIView.animate(withDuration: 0.2, delay: 0.35, options: [.allowUserInteraction]) {
            self.alpha = 1
        }
    }

    func hide() {
        layer.removeAllAnimations()
        alpha = 0
        stopAnimating()
    }
}

/// Small "tap to retry" control shown when a page fails to load.
final class RetryButton: UIButton {
    init() {
        super.init(frame: .zero)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "arrow.clockwise")
        config.title = "加载失败，轻点重试"
        config.imagePadding = 6
        config.baseForegroundColor = UIColor(white: 1, alpha: 0.6)
        configuration = config
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
