import SwiftUI
import KomaCore

/// Pushed search screen: focused field on top, results grouped by source in horizontal rows.
struct GlobalSearchView: View {
    @Environment(\.accentColor) private var accent
    @StateObject private var vm: GlobalSearchViewModel
    @FocusState private var fieldFocused: Bool
    @State private var didAutoFocus = false

    init(sources: [any MangaSource]) {
        _vm = StateObject(wrappedValue: GlobalSearchViewModel(sources: sources))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            ScrollView {
                if vm.sections.isEmpty {
                    hint
                } else {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(vm.sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didAutoFocus else { return }
            didAutoFocus = true
            // Focusing during the push transition is ignored on iOS 16; wait for it to settle.
            try? await Task.sleep(nanoseconds: 450_000_000)
            fieldFocused = true
        }
        .onDisappear { fieldFocused = false }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.Palette.secondary)
            TextField("搜索所有漫画源", text: $vm.query)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Palette.primary)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { vm.submit() }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.Palette.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .cardSurface(cornerRadius: 21, fill: Theme.Palette.elevated)
    }

    private var hint: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 30, weight: .regular))
                .foregroundColor(accent)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Theme.Palette.elevated))
            Text("输入漫画名，同时搜索所有漫画源")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    @ViewBuilder
    private func sectionView(_ section: GlobalSearchViewModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.name)
                    .font(Theme.Typography.title)
                    .foregroundColor(Theme.Palette.primary)
                if case .loaded(let items) = section.state, !items.isEmpty {
                    Text("\(items.count)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            switch section.state {
            case .loading:
                HorizontalCoverRowSkeleton(count: 4)
            case .loaded(let items) where items.isEmpty:
                inlineMessage("没有找到", retry: nil)
            case .loaded(let items):
                HorizontalCoverRow(items: items) { DiscoverRoute.manga($0) }
            case .failed(let message):
                inlineMessage(message, retry: { vm.retry(sourceId: section.id) })
            }
        }
    }

    private func inlineMessage(_ text: String, retry: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button {
                    Theme.haptic()
                    retry()
                } label: {
                    Text("重试")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Palette.elevated))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .cardSurface(cornerRadius: 12)
        .padding(.horizontal, 16)
    }
}
