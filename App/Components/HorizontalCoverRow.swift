import SwiftUI
import KomaCore

/// Horizontally scrolling row of covers with titles; each cover pushes `route(item)`.
struct HorizontalCoverRow<Route: Hashable>: View {
    let items: [MangaRef]
    let route: (MangaRef) -> Route

    static var coverWidth: CGFloat { 112 }
    static var rowHeight: CGFloat { coverWidth * 1.5 + 44 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items, id: \.self) { item in
                    NavigationLink(value: route(item)) {
                        CoverCard(item: item, width: Self.coverWidth)
                    }
                    .buttonStyle(.pressable)
                    .fadeInOnAppear(once: "row-\(item.sourceId)-\(item.id)")
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: Self.rowHeight)
    }
}

/// Skeleton placeholder matching `HorizontalCoverRow`'s geometry.
struct HorizontalCoverRowSkeleton: View {
    var count = 6

    private var width: CGFloat { HorizontalCoverRow<Int>.coverWidth }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<count, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonView()
                            .frame(width: width, height: width * 1.5)
                        SkeletonView(shape: .capsule)
                            .frame(width: width * 0.8, height: 10)
                        SkeletonView(shape: .capsule)
                            .frame(width: width * 0.5, height: 10)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollDisabled(true)
        .frame(height: HorizontalCoverRow<Int>.rowHeight)
        .accessibilityLabel("正在加载")
    }
}

/// Cover with a two-line title beneath, used by rows and grids.
struct CoverCard: View {
    let item: MangaRef
    var width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImageView(url: item.coverURL, size: CGSize(width: 160, height: 240))
            Text(item.title)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Palette.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
