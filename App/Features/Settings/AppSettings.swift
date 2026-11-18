import SwiftUI
import KomaCore

enum AppearanceOption: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AccentSwatch: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }

    static let all: [AccentSwatch] = [
        AccentSwatch(name: "珊瑚", hex: "FF6F61"),
        AccentSwatch(name: "樱花", hex: "FF8FAB"),
        AccentSwatch(name: "天空", hex: "4DA3FF"),
        AccentSwatch(name: "薄荷", hex: "3CCB9A"),
        AccentSwatch(name: "紫罗兰", hex: "8E7CFF")
    ]
}

extension Color {
    /// Parses a 6-digit RGB hex string such as "FF6F61"; falls back to the default accent.
    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if cleaned.count == 6, let value = UInt32(cleaned, radix: 16) {
            self.init(hex: value)
        } else {
            self = Theme.accent
        }
    }
}

/// User preferences, persisted in UserDefaults. The keys are also read directly by the
/// reader (see `ReaderContainerView.defaultReadingMode()`), so keep them stable.
final class AppSettings: ObservableObject {
    static let defaultAccentHex = "FF6F61"
    static let defaultCacheLimitMB = 1024
    static let cacheLimitKey = "cacheLimitMB"
    static let readingModeKey = "defaultReadingMode"
    static let keepScreenOnKey = "keepScreenOn"

    @AppStorage("appearance") var appearance: String = AppearanceOption.system.rawValue
    @AppStorage("accentHex") var accentHex: String = AppSettings.defaultAccentHex
    @AppStorage("defaultReadingMode") var defaultReadingMode: String = ReadingMode.rightToLeft.rawValue
    @AppStorage("keepScreenOn") var keepScreenOn: Bool = true
    @AppStorage("cacheLimitMB") var cacheLimitMB: Int = AppSettings.defaultCacheLimitMB

    var appearanceOption: AppearanceOption {
        AppearanceOption(rawValue: appearance) ?? .system
    }

    var accentColor: Color { Color(hexString: accentHex) }

    /// Stored values for non-UI consumers (reader, pipeline setup).
    static func storedReadingMode() -> ReadingMode {
        UserDefaults.standard.string(forKey: readingModeKey).flatMap(ReadingMode.init(rawValue:)) ?? .rightToLeft
    }

    static func storedKeepScreenOn() -> Bool {
        UserDefaults.standard.object(forKey: keepScreenOnKey) as? Bool ?? true
    }

    static func storedCacheLimitMB() -> Int {
        let value = UserDefaults.standard.integer(forKey: cacheLimitKey)
        return value > 0 ? value : defaultCacheLimitMB
    }
}
