import Foundation

/// Decides when appended items (the next chapter) may be applied to the page view.
public enum ReaderAppendPolicy {
    /// In right-to-left mode the flipped layout shifts every existing item's x when items are appended,
    /// which breaks an in-flight deceleration or scroll animation, so the append waits until scrolling stops.
    /// Other modes append at the end without moving anything and apply immediately.
    public static func shouldDeferAppend(
        mode: ReadingMode,
        isDragging: Bool,
        isDecelerating: Bool,
        isAnimatingScroll: Bool
    ) -> Bool {
        guard mode == .rightToLeft else { return false }
        return isDragging || isDecelerating || isAnimatingScroll
    }
}
