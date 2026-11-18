import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }
}

enum Theme {
    static let accent = Color(hex: 0xFF6F61)
    static let coverRadius: CGFloat = 10
    static let cardRadius: CGFloat = 16
    static let hairlineWidth: CGFloat = 0.5
    static let pressScale: CGFloat = 0.97
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Adaptive color tokens. Dark values are the primary design; light values are equivalents.
    enum Palette {
        static let background = adaptive(dark: 0x0D0D10, light: 0xF7F7F8)
        static let card = adaptive(dark: 0x17171C, light: 0xFFFFFF)
        static let elevated = adaptive(dark: 0x1C1C22, light: 0xF0F0F2)
        static let hairline = adaptive(dark: 0x24242A, light: 0xE4E4E8)
        static let primary = adaptive(dark: 0xF2F2F5, light: 0x111114)
        static let secondary = adaptive(dark: 0x8A8A94, light: 0x6B6B73)
        static let muted = adaptive(dark: 0x5A5A62, light: 0xA0A0A8)
        static let adultTag = Color(hex: 0xFF5A5F)
        /// Highlight band swept across skeleton placeholders.
        static let shimmer = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.06)
                : UIColor(white: 1, alpha: 0.75)
        })

        private static func adaptive(dark: UInt32, light: UInt32) -> Color {
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
            })
        }
    }

    /// Type scale; at most three weights (regular, medium, semibold).
    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .semibold)
        static let title = Font.system(size: 20, weight: .semibold)
        static let body = Font.system(size: 15, weight: .regular)
        static let footnote = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 12, weight: .regular)
    }

    @MainActor private static var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    /// Plays an impact haptic using a cached, pre-warmed generator per style.
    @MainActor
    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator: UIImpactFeedbackGenerator
        if let cached = generators[style] {
            generator = cached
        } else {
            generator = UIImpactFeedbackGenerator(style: style)
            generators[style] = generator
        }
        generator.impactOccurred()
        generator.prepare()
    }
}

/// Scale-down press feedback (0.97) used by cards, chips and rows.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Theme.pressScale : 1)
            .animation(Theme.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Fades (and slightly lifts) a view in the first time it appears.
private struct FadeInOnAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 8)
            .onAppear {
                guard !visible else { return }
                withAnimation(.easeOut(duration: 0.28)) { visible = true }
            }
    }
}

/// Ids that have already faded in, so lazily recycled cells don't fade (and flicker) again.
/// Only touched from view code on the main thread.
private enum FadeRegistry {
    static var seen = Set<AnyHashable>()
}

private struct FadeInOnce: ViewModifier {
    let id: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible: Bool

    init(id: AnyHashable) {
        self.id = id
        _visible = State(initialValue: FadeRegistry.seen.contains(id))
    }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 8)
            .onAppear {
                guard !visible else { return }
                FadeRegistry.seen.insert(id)
                withAnimation(.easeOut(duration: 0.28)) { visible = true }
            }
    }
}

extension View {
    func fadeInOnAppear() -> some View {
        modifier(FadeInOnAppear())
    }

    /// Fades in only the first time a view with `id` appears during this app session.
    func fadeInOnAppear<ID: Hashable>(once id: ID) -> some View {
        modifier(FadeInOnce(id: AnyHashable(id)))
    }

    /// Rounded card surface with the hairline border used throughout the app.
    func cardSurface(cornerRadius: CGFloat = Theme.cardRadius, fill: Color = Theme.Palette.card) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.hairlineWidth)))
    }
}

private struct AccentColorKey: EnvironmentKey {
    static let defaultValue = Theme.accent
}

extension EnvironmentValues {
    /// The user-selected accent color (see AppSettings); defaults to coral.
    var accentColor: Color {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
}
