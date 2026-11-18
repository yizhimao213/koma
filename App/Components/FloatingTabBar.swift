import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case library, discover, history, downloads, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "书架"
        case .discover: return "发现"
        case .history: return "历史"
        case .downloads: return "下载"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .library: return "books.vertical"
        case .discover: return "safari"
        case .history: return "clock"
        case .downloads: return "arrow.down.circle"
        case .settings: return "gearshape"
        }
    }

    var selectedSymbol: String { symbol + ".fill" }
}

/// Tracks which screens currently want the floating tab bar hidden.
///
/// An environment object is used rather than a PreferenceKey because preferences do not
/// reliably cross the UIKit hosting boundary between TabView pages and their container.
@MainActor
final class TabBarVisibility: ObservableObject {
    @Published private(set) var isHidden = false
    private var hiders = Set<UUID>()

    func set(_ hidden: Bool, for token: UUID) {
        if hidden {
            hiders.insert(token)
        } else {
            hiders.remove(token)
        }
        let next = !hiders.isEmpty
        if next != isHidden { isHidden = next }
    }
}

private struct TabBarHiddenModifier: ViewModifier {
    let hidden: Bool
    @EnvironmentObject private var visibility: TabBarVisibility
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { visibility.set(hidden, for: token) }
            .onChange(of: hidden) { visibility.set($0, for: token) }
            .onDisappear { visibility.set(false, for: token) }
    }
}

extension View {
    /// Hides the floating tab bar while `hidden` is true and this view is on screen.
    func tabBarHidden(_ hidden: Bool) -> some View {
        modifier(TabBarHiddenModifier(hidden: hidden))
    }
}

/// Floating capsule tab bar that replaces the system tab bar.
struct FloatingTabBar: View {
    @Environment(\.accentColor) private var accent
    @Binding var selection: AppTab

    static let barHeight: CGFloat = 56
    static let bottomGap: CGFloat = 8
    /// Bottom inset each tab's content reserves so nothing sits under the bar.
    static let reservedHeight: CGFloat = 72

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.barHeight)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.Palette.elevated)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.hairlineWidth))
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, Self.bottomGap)
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        return Button {
            guard tab != selection else { return }
            Theme.haptic(.light)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 24)
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? accent : Theme.Palette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
