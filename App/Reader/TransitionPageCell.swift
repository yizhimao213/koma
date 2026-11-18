import UIKit
import KomaCore

/// Shown between chapters: "第X话 读完了" and the next chapter (or the end of the series).
final class TransitionPageCell: UICollectionViewCell {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let hintLabel = UILabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentView.backgroundColor = .black

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white
        detailLabel.font = .systemFont(ofSize: 15)
        detailLabel.textColor = UIColor(white: 1, alpha: 0.7)
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = UIColor(white: 1, alpha: 0.4)
        for label in [titleLabel, detailLabel, hintLabel] {
            label.textAlignment = .center
            label.numberOfLines = 2
            stack.addArrangedSubview(label)
        }
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(24, after: detailLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(from chapter: Chapter, to next: Chapter?) {
        titleLabel.text = "\(Self.name(of: chapter)) 读完了"
        if let next {
            detailLabel.text = "下一话：\(next.title)"
            hintLabel.text = "继续翻页阅读下一话"
            hintLabel.isHidden = false
        } else {
            detailLabel.text = "已经是最后一话了"
            hintLabel.isHidden = true
        }
    }

    static func name(of chapter: Chapter) -> String {
        if let number = chapter.number {
            let text = number == number.rounded() ? String(Int(number)) : String(number)
            return "第\(text)话"
        }
        return chapter.title
    }
}
