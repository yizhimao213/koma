import SwiftUI

enum SkeletonShape {
    case rounded(CGFloat)
    case capsule
    case circle

    var shape: AnyShape {
        switch self {
        case .rounded(let radius): return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule: return AnyShape(Capsule(style: .continuous))
        case .circle: return AnyShape(Circle())
        }
    }
}

/// Placeholder block with a subtle shimmer sweep (static when Reduce Motion is on).
struct SkeletonView: View {
    var shape: SkeletonShape = .rounded(Theme.coverRadius)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        shape.shape
            .fill(Theme.Palette.elevated)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, Theme.Palette.shimmer, .clear],
                            startPoint: .leading,
                            endPoint: .trailing)
                        .frame(width: proxy.size.width)
                        .offset(x: phase * proxy.size.width * 1.3)
                    }
                    .onAppear {
                        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            }
            .clipShape(shape.shape)
            .accessibilityHidden(true)
    }
}
