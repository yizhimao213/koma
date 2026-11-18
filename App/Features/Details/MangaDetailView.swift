import SwiftUI
import NukeUI
import KomaCore

private struct ReaderRoute: Identifiable {
    let id = UUID()
    let chapterId: String
    let page: Int
}

struct MangaDetailView: View {
    let ref: MangaRef
    let namespace: Namespace.ID?
    let onClose: (() -> Void)?

    @StateObject private var vm: MangaDetailViewModel
    @State private var descriptionExpanded = false
    @State private var sortDescending = false
    @State private var route: ReaderRoute?

    init(ref: MangaRef, env: AppEnvironment, namespace: Namespace.ID? = nil, onClose: (() -> Void)? = nil) {
        self.ref = ref
        self.namespace = namespace
        self.onClose = onClose
        _vm = StateObject(wrappedValue: MangaDetailViewModel(ref: ref, env: env))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            List {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                chapterHeader
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(displayedChapters, id: \.id) { chapter in
                    chapterRow(chapter)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            if let onClose {
                Button {
                    Theme.haptic()
                    onClose()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.regularMaterial))
                }
                .buttonStyle(.pressable)
                .padding(.leading, 16)
                .padding(.top, 8)
            }
        }
        .task { await vm.load() }
        .fullScreenCover(item: $route, onDismiss: { vm.refreshState() }) { route in
            ReaderContainerView(
                manga: ref,
                chapters: vm.chapters,
                startChapterId: route.chapterId,
                startPage: route.page)
        }
    }

    private var coverURL: URL? { vm.details?.ref.coverURL ?? ref.coverURL }

    private var displayedChapters: [Chapter] {
        sortDescending ? Array(vm.chapters.reversed()) : vm.chapters
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            Color(.systemBackground)
            GeometryReader { proxy in
                LazyImage(url: coverURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: proxy.size.width, height: 420)
                .clipped()
                .blur(radius: 40)
                .opacity(0.5)
                .overlay(
                    LinearGradient(
                        colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                        startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 16) {
                coverView
                    .frame(width: 130)
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(ref.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(3)
                    if let author = vm.details?.author, !author.isEmpty {
                        Text(author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let status = vm.details?.status, status != .unknown {
                        Text(status == .ongoing ? "连载中" : "已完结")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 56)

            if let tags = vm.details?.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(.secondarySystemFill)))
                        }
                    }
                }
            }

            actionButtons

            if let description = vm.details?.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(description)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(descriptionExpanded ? nil : 3)
                    Text(descriptionExpanded ? "收起" : "展开")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    Theme.haptic()
                    withAnimation(Theme.spring) { descriptionExpanded.toggle() }
                }
            }

            if let errorText = vm.errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var coverView: some View {
        let cover = CoverImageView(url: coverURL, size: CGSize(width: 390, height: 585))
        if let namespace {
            cover.matchedGeometryEffect(id: "\(ref.sourceId)/\(ref.id)", in: namespace)
        } else {
            cover
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                guard let target = vm.resumeTarget else { return }
                Theme.haptic(.medium)
                route = ReaderRoute(chapterId: target.chapter.id, page: target.page)
            } label: {
                Text(vm.resumeLabel())
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.pressable)
            .disabled(vm.chapters.isEmpty)
            .opacity(vm.chapters.isEmpty ? 0.5 : 1)

            Button {
                Theme.haptic()
                withAnimation(Theme.spring) { vm.toggleLibrary() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: vm.inLibrary ? "checkmark" : "plus")
                    Text(vm.inLibrary ? "已在书架" : "加入书架")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(vm.inLibrary ? .secondary : Theme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(
                    Capsule().fill(vm.inLibrary ? Color(.secondarySystemFill) : Theme.accent.opacity(0.14)))
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: - Chapters

    private var chapterHeader: some View {
        HStack {
            Text("共 \(vm.chapters.count) 话")
                .font(.headline)
            Spacer()
            Button {
                Theme.haptic()
                withAnimation(Theme.spring) { sortDescending.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortDescending ? "倒序" : "正序")
                }
                .font(.subheadline)
                .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let isRead = vm.readIds.contains(chapter.id)
        return Button {
            Theme.haptic()
            route = ReaderRoute(chapterId: chapter.id, page: vm.startPage(for: chapter))
        } label: {
            HStack {
                Text(chapter.title)
                    .font(.body)
                    .foregroundColor(isRead ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                if isRead {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button {
                Theme.haptic()
                vm.setRead(chapter, !isRead)
            } label: {
                Label(isRead ? "标记未读" : "标记已读", systemImage: isRead ? "circle" : "checkmark.circle")
            }
            .tint(Theme.accent)
        }
    }
}
