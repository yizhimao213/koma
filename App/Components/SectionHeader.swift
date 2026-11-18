import SwiftUI

/// Section title with an optional trailing "全部" style action.
struct SectionHeader: View {
    let title: String
    var actionTitle: String = "全部"
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundColor(Theme.Palette.primary)
            Spacer(minLength: 12)
            if let action {
                Button {
                    Theme.haptic()
                    action()
                } label: {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Palette.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 16)
    }
}
