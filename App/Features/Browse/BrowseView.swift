import SwiftUI
import KomaCore

struct BrowseView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                ForEach(env.sources.all, id: \.id) { source in
                    NavigationLink {
                        SourceGridView(source: source)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "folder.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .font(.body.weight(.medium))
                                Text("浏览已导入的漫画")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("发现")
        }
    }
}

private struct SourceGridView: View {
    let source: any MangaSource
    @EnvironmentObject private var env: AppEnvironment
    @State private var items: [MangaRef] = []
    @State private var page = 1
    @State private var hasNext = false
    @State private var isLoading = true
    @State private var failed = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        Group {
            if items.isEmpty && !isLoading {
                EmptyStateView(
                    symbol: failed ? "exclamationmark.triangle" : "books.vertical",
                    title: failed ? "加载失败" : "这里还没有漫画",
                    actionTitle: nil,
                    action: nil)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items, id: \.self) { item in
                            NavigationLink {
                                MangaDetailView(ref: item, env: env)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    CoverImageView(url: item.coverURL, size: CGSize(width: 240, height: 360))
                                    Text(item.title)
                                        .font(.footnote.weight(.medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(.pressable)
                            .onAppear {
                                if item == items.last, hasNext, !isLoading {
                                    Task { await load(page: page + 1) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(page: 1) }
    }

    private func load(page target: Int) async {
        isLoading = true
        do {
            let result = try await source.popular(page: target)
            items = target == 1 ? result.items : items + result.items
            page = target
            hasNext = result.hasNextPage
            failed = false
        } catch {
            failed = true
        }
        isLoading = false
    }
}
