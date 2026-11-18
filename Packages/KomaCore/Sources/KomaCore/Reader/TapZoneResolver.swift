import CoreGraphics
import Foundation

public enum ReadingMode: String, Codable, CaseIterable, Sendable {
    case leftToRight, rightToLeft, vertical, webtoon
}

public enum TapAction: Equatable, Sendable {
    case next, previous, toggleMenu
}

public struct TapZoneResolver: Sendable {
    public init() {}

    public func action(for point: CGPoint, in size: CGSize, mode: ReadingMode) -> TapAction {
        switch mode {
        case .leftToRight, .rightToLeft:
            guard size.width > 0 else { return .toggleMenu }
            let ratio = point.x / size.width
            let left: TapAction = mode == .leftToRight ? .previous : .next
            let right: TapAction = mode == .leftToRight ? .next : .previous
            if ratio < 0.3 { return left }
            if ratio > 0.7 { return right }
            return .toggleMenu
        case .vertical, .webtoon:
            guard size.height > 0 else { return .toggleMenu }
            let ratio = point.y / size.height
            if ratio < 0.3 { return .previous }
            if ratio > 0.7 { return .next }
            return .toggleMenu
        }
    }
}
