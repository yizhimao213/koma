import UIKit
import Nuke

/// Full-screen page for the paged modes: pinch (1–4×) and double-tap (1 ↔ 2.5×) zoom.
final class ZoomingPageCell: UICollectionViewCell, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = DelayedSpinner()
    private let retryButton = RetryButton()
    private let loader = PageImageLoader()
    private var request: ImageRequest?
    private var lastLayoutSize: CGSize = .zero

    /// Reports the loaded image's height / width ratio.
    var onAspect: ((CGFloat) -> Void)?

    private(set) lazy var doubleTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentView.backgroundColor = .black

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1  // raised to 4 once an image is shown
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .black
        scrollView.addGestureRecognizer(doubleTap)
        contentView.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.alpha = 0
        scrollView.addSubview(imageView)

        contentView.addSubview(spinner)
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        contentView.addSubview(retryButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(request: ImageRequest) {
        self.request = request
        load()
    }

    private func load() {
        guard let request else { return }
        retryButton.isHidden = true
        loader.load(request) { [weak self] image, cached in
            self?.show(image, cached: cached)
        }
        if imageView.image == nil {
            spinner.showAfterDelay()
        }
    }

    private func show(_ image: UIImage?, cached: Bool) {
        spinner.hide()
        guard let image else {
            retryButton.isHidden = false
            return
        }
        imageView.image = image
        scrollView.maximumZoomScale = 4
        if image.size.width > 0 {
            onAspect?(image.size.height / image.size.width)
        }
        layoutImage()
        if cached {
            imageView.alpha = 1
        } else {
            imageView.alpha = 0
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                self.imageView.alpha = 1
            }
        }
    }

    @objc private func retry() {
        load()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loader.cancel()
        request = nil
        onAspect = nil
        imageView.layer.removeAllAnimations()
        imageView.image = nil
        imageView.alpha = 0
        spinner.hide()
        retryButton.isHidden = true
        scrollView.setZoomScale(1, animated: false)
        scrollView.maximumZoomScale = 1
    }

    func resetZoom() {
        guard scrollView.zoomScale != 1 else { return }
        scrollView.setZoomScale(1, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        retryButton.sizeToFit()
        retryButton.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if scrollView.frame != bounds {
            scrollView.frame = bounds
        }
        if lastLayoutSize != bounds.size {
            lastLayoutSize = bounds.size
            scrollView.setZoomScale(1, animated: false)
            layoutImage()
        }
    }

    /// Sizes the image view to the aspect-fit rect at zoom 1 and centers it.
    private func layoutImage() {
        let bounds = scrollView.bounds.size
        guard bounds.width > 0, bounds.height > 0 else { return }
        var fitted = bounds
        if let size = imageView.image?.size, size.width > 0, size.height > 0 {
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            fitted = CGSize(width: size.width * scale, height: size.height * scale)
        }
        if scrollView.zoomScale != 1 {
            scrollView.setZoomScale(1, animated: false)
        }
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = imageView.frame.size
        centerImage()
        // contentInset alone leaves contentOffset at (0, 0), which is out of range until the first touch.
        let inset = scrollView.contentInset
        scrollView.contentOffset = CGPoint(x: -inset.left, y: -inset.top)
    }

    private func centerImage() {
        let bounds = scrollView.bounds.size
        let content = imageView.frame.size
        let horizontal = max(0, (bounds.width - content.width) / 2)
        let vertical = max(0, (bounds.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard imageView.image != nil else { return }
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let target: CGFloat = 2.5
        let point = gesture.location(in: imageView)
        let size = CGSize(width: scrollView.bounds.width / target, height: scrollView.bounds.height / target)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        scrollView.zoom(to: rect, animated: true)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }
}
