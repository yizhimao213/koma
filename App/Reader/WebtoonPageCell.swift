import UIKit
import Nuke

/// One strip of the continuous webtoon mode. Height is driven by the layout (width × aspect).
final class WebtoonPageCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let spinner = DelayedSpinner()
    private let retryButton = RetryButton()
    private let loader = PageImageLoader()
    private var request: ImageRequest?

    /// Reports the loaded image's height / width ratio.
    var onAspect: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        imageView.alpha = 0
        contentView.addSubview(imageView)
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
        if image.size.width > 0 {
            onAspect?(image.size.height / image.size.width)
        }
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
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        imageView.frame = bounds
        // Keep the indicator inside the first screenful of tall placeholders.
        let y = min(bounds.midY, 160)
        spinner.center = CGPoint(x: bounds.midX, y: y)
        retryButton.sizeToFit()
        retryButton.center = CGPoint(x: bounds.midX, y: y)
    }
}
