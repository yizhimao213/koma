import SwiftUI
import Nuke
import KomaCore

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var env: AppEnvironment
    @State private var cacheBytes: Int = 0
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: $settings.appearance) {
                        ForEach(AppearanceOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("主题色")
                        HStack(spacing: 16) {
                            ForEach(AccentSwatch.all) { swatch in
                                swatchButton(swatch)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("阅读") {
                    Picker("默认阅读模式", selection: $settings.defaultReadingMode) {
                        ForEach(ReadingMode.allCases, id: \.rawValue) { mode in
                            Text(Self.title(for: mode)).tag(mode.rawValue)
                        }
                    }
                    Toggle("阅读时保持屏幕常亮", isOn: $settings.keepScreenOn)
                }

                Section("存储") {
                    HStack {
                        Text("图片缓存")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))
                            .foregroundColor(.secondary)
                    }
                    Button("清除缓存", role: .destructive) {
                        confirmClear = true
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(KomaCore.version).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .animation(Theme.spring, value: settings.accentHex)
        }
        .onAppear { refreshCacheSize() }
        .confirmationDialog("清除图片缓存？已导入的漫画不会被删除。", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除缓存", role: .destructive) {
                ImagePipeline.shared.cache.removeAll()
                Theme.haptic(.medium)
                env.toast.show("缓存已清除")
                refreshCacheSize()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func swatchButton(_ swatch: AccentSwatch) -> some View {
        let selected = settings.accentHex.caseInsensitiveCompare(swatch.hex) == .orderedSame
        return Button {
            Theme.haptic()
            withAnimation(Theme.spring) { settings.accentHex = swatch.hex }
        } label: {
            Circle()
                .fill(Color(hexString: swatch.hex))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(selected ? 1 : 0))
                .overlay(
                    Circle()
                        .stroke(Color(hexString: swatch.hex), lineWidth: 2)
                        .padding(-4)
                        .opacity(selected ? 1 : 0))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(swatch.name)
    }

    private func refreshCacheSize() {
        let cache = ImagePipeline.shared.configuration.dataCache as? DataCache
        Task {
            let size = await Task.detached(priority: .utility) { cache?.totalSize ?? 0 }.value
            cacheBytes = size
        }
    }

    static func title(for mode: ReadingMode) -> String {
        switch mode {
        case .leftToRight: return "从左到右"
        case .rightToLeft: return "从右到左"
        case .vertical: return "纵向翻页"
        case .webtoon: return "条漫"
        }
    }
}
