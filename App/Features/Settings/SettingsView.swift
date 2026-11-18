import SwiftUI
import Nuke
import KomaCore

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var env: AppEnvironment
    @State private var cacheBytes: Int = 0
    @State private var confirmClear = false
    @State private var apiDraft = ""
    @State private var uploadsDraft = ""
    @State private var apiInvalid = false
    @State private var uploadsInvalid = false
    @State private var confirmAdult = false
    @FocusState private var focusedField: URLField?
    @State private var probing = false
    @State private var probeResults: [ProbeResult] = []

    private enum URLField: Hashable { case api, uploads }

    private struct LanguageOption {
        let code: String
        let title: String
    }

    private static let languageOptions: [LanguageOption] = [
        LanguageOption(code: "zh", title: "简体中文"),
        LanguageOption(code: "zh-hk", title: "繁體中文"),
        LanguageOption(code: "en", title: "English"),
        LanguageOption(code: "ja", title: "日本語")
    ]

    private var invalidLabel: some View {
        Text("地址格式不正确")
            .font(.caption)
            .foregroundColor(.red)
    }

    private var adultBinding: Binding<Bool> {
        Binding(
            get: { settings.showAdult },
            set: { newValue in
                if newValue && !settings.adultConfirmed {
                    confirmAdult = true
                } else {
                    settings.showAdult = newValue
                }
            })
    }

    /// All known language codes in the user's stored order.
    private var orderedCodes: [String] {
        let known = Self.languageOptions.map(\.code)
        var order = settings.languageOrder.split(separator: ",").map(String.init).filter { known.contains($0) }
        for code in known where !order.contains(code) { order.append(code) }
        return order
    }

    private var enabledCodes: [String] {
        settings.languagePriority.split(separator: ",").map(String.init)
    }

    private func saveLanguages(order: [String], enabled: Set<String>) {
        settings.languageOrder = order.joined(separator: ",")
        settings.languagePriority = order.filter { enabled.contains($0) }.joined(separator: ",")
    }

    @ViewBuilder
    private var languageRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("章节语言优先级")
            Text("按从上到下的顺序优先选择")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        let codes = orderedCodes
        ForEach(Array(codes.enumerated()), id: \.element) { index, code in
            HStack(spacing: 12) {
                Toggle(Self.languageOptions.first { $0.code == code }?.title ?? code, isOn: Binding(
                    get: { enabledCodes.contains(code) },
                    set: { on in
                        var enabled = Set(enabledCodes)
                        if on { enabled.insert(code) } else { enabled.remove(code) }
                        saveLanguages(order: codes, enabled: enabled)
                    }))
                Button {
                    moveLanguage(at: index, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                Button {
                    moveLanguage(at: index, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == codes.count - 1)
            }
        }
    }

    private func moveLanguage(at index: Int, by delta: Int) {
        var codes = orderedCodes
        let target = index + delta
        guard codes.indices.contains(index), codes.indices.contains(target) else { return }
        codes.swapAt(index, target)
        saveLanguages(order: codes, enabled: Set(enabledCodes))
    }

    private func commitURL(draft: Binding<String>, invalid: Binding<Bool>, store: ReferenceWritableKeyPath<AppSettings, String>) {
        let text = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            settings[keyPath: store] = ""
            draft.wrappedValue = ""
            invalid.wrappedValue = false
        } else if AppSettings.validatedURL(text) != nil {
            settings[keyPath: store] = text
            draft.wrappedValue = text
            invalid.wrappedValue = false
        } else {
            invalid.wrappedValue = true
        }
    }

    private func commitDrafts() {
        commitURL(draft: $apiDraft, invalid: $apiInvalid, store: \AppSettings.apiBaseURL)
        commitURL(draft: $uploadsDraft, invalid: $uploadsInvalid, store: \AppSettings.uploadsBaseURL)
    }

    private func runProbe() {
        guard !probing else { return }
        probing = true
        probeResults = []
        let network = AppSettings.currentNetworkSettings(isExpensive: NetworkPathMonitor.isExpensiveSnapshot)
        Task { @MainActor in
            let probe = ConnectivityProbe(
                client: URLSessionHTTPClient(maxRetries: 0),
                settings: network,
                now: { Date().timeIntervalSinceReferenceDate })
            let results = await probe.run()
            probeResults = results
            probing = false
        }
    }

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

                Section("内容") {
                    Toggle("显示 18+ 内容", isOn: adultBinding)
                }

                Section("网络") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(NetworkSettings.default.apiBaseURL.absoluteString, text: $apiDraft)
                            .urlFieldStyle()
                            .focused($focusedField, equals: .api)
                            .onChange(of: apiDraft) { _ in apiInvalid = false }
                            .onSubmit { commitURL(draft: $apiDraft, invalid: $apiInvalid, store: \AppSettings.apiBaseURL) }
                        if apiInvalid { invalidLabel }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(NetworkSettings.default.uploadsBaseURL.absoluteString, text: $uploadsDraft)
                            .urlFieldStyle()
                            .focused($focusedField, equals: .uploads)
                            .onChange(of: uploadsDraft) { _ in uploadsInvalid = false }
                            .onSubmit { commitURL(draft: $uploadsDraft, invalid: $uploadsInvalid, store: \AppSettings.uploadsBaseURL) }
                        if uploadsInvalid { invalidLabel }
                    }
                    Button("恢复默认") {
                        apiDraft = ""
                        uploadsDraft = ""
                        settings.apiBaseURL = ""
                        settings.uploadsBaseURL = ""
                    }
                    .disabled(apiDraft.isEmpty && uploadsDraft.isEmpty)
                    Picker("省流模式", selection: $settings.dataSaverMode) {
                        Text("自动").tag("auto")
                        Text("开").tag("on")
                        Text("关").tag("off")
                    }
                    languageRows
                    Button {
                        runProbe()
                    } label: {
                        HStack {
                            Text("测试连接")
                            if probing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(probing)
                    ForEach(probeResults, id: \.name) { result in
                        HStack {
                            Text(result.name)
                            Spacer()
                            if let ms = result.latencyMs {
                                Text("\(ms) ms").foregroundColor(.secondary)
                            } else {
                                Text(result.error ?? "失败").foregroundColor(.red)
                            }
                        }
                        .font(.subheadline)
                    }
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
        .onChange(of: focusedField) { _ in commitDrafts() }
        .onDisappear { commitDrafts() }
        .onAppear {
            apiDraft = settings.apiBaseURL
            uploadsDraft = settings.uploadsBaseURL
            refreshCacheSize()
        }
        .alert("确认你已年满 18 岁", isPresented: $confirmAdult) {
            Button("取消", role: .cancel) {}
            Button("我已年满 18 岁") {
                settings.adultConfirmed = true
                settings.showAdult = true
            }
        } message: {
            Text("18+ 内容可能包含成人向内容，仅限成年人浏览。")
        }
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
        Task { @MainActor in
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

private extension View {
    func urlFieldStyle() -> some View {
        self
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.done)
    }
}
