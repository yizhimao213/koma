import SwiftUI

/// Error state with a message and a "重试" button.
struct RetryView: View {
    @Environment(\.accentColor) private var accent
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .regular))
                .foregroundColor(Theme.Palette.secondary)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Theme.Palette.elevated))
                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: Theme.hairlineWidth))
            Text("加载失败")
                .font(Theme.Typography.title)
                .foregroundColor(Theme.Palette.primary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
            Button {
                Theme.haptic()
                retry()
            } label: {
                Text("重试")
                    .font(Theme.Typography.body.weight(.medium))
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}
