import SwiftUI

struct EmptyStateView: View {
    @Environment(\.accentColor) private var accent
    let symbol: String
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundColor(accent)
                .frame(width: 96, height: 96)
                .background(Circle().fill(accent.opacity(0.12)))
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            if let actionTitle, let action {
                Button {
                    Theme.haptic()
                    action()
                } label: {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.pressable)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
