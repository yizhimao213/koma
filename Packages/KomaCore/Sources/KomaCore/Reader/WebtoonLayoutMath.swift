import CoreGraphics
import Foundation

/// Pure geometry used by the webtoon (continuous vertical) reader.
public enum WebtoonLayoutMath {
    /// Height / width ratio used until a page's real aspect is known.
    public static let placeholderAspect: CGFloat = 1.5
    public static let minZoom: CGFloat = 1
    public static let maxZoom: CGFloat = 3

    public struct HeightChange: Equatable, Sendable {
        public var minY: CGFloat
        public var oldHeight: CGFloat
        public var newHeight: CGFloat

        public init(minY: CGFloat, oldHeight: CGFloat, newHeight: CGFloat) {
            self.minY = minY
            self.oldHeight = oldHeight
            self.newHeight = newHeight
        }
    }

    public static func height(forWidth width: CGFloat, aspect: CGFloat?) -> CGFloat {
        guard let aspect, aspect > 0 else { return width * placeholderAspect }
        return width * aspect
    }

    /// Content offset delta that keeps visible content still when item heights change:
    /// the sum of height deltas of items whose top lies above `visibleTop`.
    public static func contentOffsetAdjustment(for changes: [HeightChange], visibleTop: CGFloat) -> CGFloat {
        changes.reduce(0) { sum, change in
            change.minY < visibleTop ? sum + (change.newHeight - change.oldHeight) : sum
        }
    }

    /// Zoom applied as `transform = translate(translationX, 0) * scale(scale)` about the view's center,
    /// with symmetric vertical content insets so the whole content stays reachable.
    public struct ZoomState: Equatable, Sendable {
        public var scale: CGFloat
        public var translationX: CGFloat
        public var verticalInset: CGFloat
        public var contentOffsetY: CGFloat

        public init(scale: CGFloat, translationX: CGFloat, verticalInset: CGFloat, contentOffsetY: CGFloat) {
            self.scale = scale
            self.translationX = translationX
            self.verticalInset = verticalInset
            self.contentOffsetY = contentOffsetY
        }
    }

    public static func verticalInset(scale: CGFloat, viewHeight: CGFloat) -> CGFloat {
        viewHeight / 2 * (1 - 1 / scale)
    }

    public static func maxTranslationX(scale: CGFloat, viewWidth: CGFloat) -> CGFloat {
        (scale - 1) * viewWidth / 2
    }

    /// Content point (scroll view coordinates) displayed at `point` (container coordinates).
    public static func contentPoint(at point: CGPoint, state: ZoomState, viewSize: CGSize) -> CGPoint {
        let cx = viewSize.width / 2
        let cy = viewSize.height / 2
        let vx = cx + (point.x - cx - state.translationX) / state.scale
        let vy = cy + (point.y - cy) / state.scale
        return CGPoint(x: vx, y: state.contentOffsetY + vy)
    }

    /// Zoom state at `scale` (clamped) that shows `anchorContent` at container point `point`, clamped to the content.
    public static func zoom(
        scale: CGFloat,
        anchorContent: CGPoint,
        at point: CGPoint,
        viewSize: CGSize,
        contentHeight: CGFloat
    ) -> ZoomState {
        let s = min(max(scale, minZoom), maxZoom)
        let cx = viewSize.width / 2
        let cy = viewSize.height / 2
        let maxTx = maxTranslationX(scale: s, viewWidth: viewSize.width)
        let tx = min(max(point.x - cx - s * (anchorContent.x - cx), -maxTx), maxTx)
        let inset = verticalInset(scale: s, viewHeight: viewSize.height)
        let vy = cy + (point.y - cy) / s
        let minOffset = -inset
        let maxOffset = max(minOffset, contentHeight - viewSize.height + inset)
        let offset = min(max(anchorContent.y - vy, minOffset), maxOffset)
        return ZoomState(scale: s, translationX: tx, verticalInset: inset, contentOffsetY: offset)
    }
}
