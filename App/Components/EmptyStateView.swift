import SwiftUI

struct EmptyStateView: View {
    @Environment(\.accentColor) private var accent
    let symbol: String
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundColor(accent)
                .frame(width: 88, height: 88)
                .background(Circle().fill(Theme.Palette.elevated))
                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: Theme.hairlineWidth))
            Text(title)
                .font(Theme.Typography.body.weight(.medium))
                .foregroundColor(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button {
                    Theme.haptic()
                    action()
                } label: {
                    Text(actionTitle)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.pressable)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
