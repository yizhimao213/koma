import SwiftUI
import Combine
import KomaCore

/// Full-width "今日推荐" carousel: deep cover-tone background, text at left, cover at right,
/// auto-advancing every 5 s (paused while dragging, stopped off screen or in background).
struct HeroCarousel: View {
    let items: [MangaRef]
    let details: [String: MangaDetails]
    let onSlideVisible: (MangaRef) -> Void

    static let height: CGFloat = 220
    private static let interval: TimeInterval = 5

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = 0
    @State private var isVisible = false
    @State private var isDragging = false
    @State private var lastInteraction = Date.distantPast
    @State private var timer = Timer.publish(every: HeroCarousel.interval, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    NavigationLink(value: DiscoverRoute.manga(item)) {
                        HeroSlide(item: item, details: details[item.id])
                    }
                    .buttonStyle(.pressable)
                    .padding(.horizontal, 16)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: Self.height)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        isDragging = true
                        lastInteraction = Date()
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastInteraction = Date()
                    })
            indicators
        }
        .onAppear {
            isVisible = true
            restartTimer()
            notifyVisible(selection)
        }
        .onDisappear {
            isVisible = false
            stopTimer()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && isVisible {
                restartTimer()
            } else {
                stopTimer()
            }
        }
        .onChange(of: selection) { index in
            notifyVisible(index)
        }
        .onChange(of: items.count) { count in
            if selection >= count { selection = 0 }
        }
        .onReceive(timer) { _ in advance() }
    }

    private var indicators: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == selection ? Theme.Palette.primary : Theme.Palette.muted.opacity(0.6))
                    .frame(width: index == selection ? 18 : 6, height: 6)
            }
        }
        .animation(Theme.spring, value: selection)
        .accessibilityElement()
        .accessibilityLabel("第 \(selection + 1) 页，共 \(items.count) 页")
    }

    private func advance() {
        guard isVisible, !isDragging, items.count > 1, scenePhase == .active else { return }
        // Give the user a full interval after any manual swipe before auto-advancing again.
        guard Date().timeIntervalSince(lastInteraction) >= Self.interval else { return }
        let next = (selection + 1) % items.count
        if reduceMotion {
            selection = next
        } else {
            withAnimation(.easeInOut(duration: 0.45)) { selection = next }
        }
    }

    private func notifyVisible(_ index: Int) {
        guard items.indices.contains(index) else { return }
        onSlideVisible(items[index])
        // Warm the next slide's details too, so its tags are ready when it slides in.
        if items.count > 1 {
            onSlideVisible(items[(index + 1) % items.count])
        }
    }

    private func restartTimer() {
        timer.upstream.connect().cancel()
        timer = Timer.publish(every: Self.interval, on: .main, in: .common).autoconnect()
    }

    private func stopTimer() {
        timer.upstream.connect().cancel()
    }
}

/// One carousel page.
private struct HeroSlide: View {
    let item: MangaRef
    let details: MangaDetails?

    @State private var tone: Color?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(tone ?? Theme.Palette.elevated)
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.black.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("今日推荐")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Color.white.opacity(0.65))
                    Text(item.title)
                        .font(Theme.Typography.title)
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    tagLine
                    Spacer(minLength: 0)
                    if let status = statusText {
                        Text(status)
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Color.white.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                CoverImageView(url: item.coverURL, size: CGSize(width: 130, height: 195))
                    .frame(width: 118)
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .padding(18)
        }
        .frame(height: HeroCarousel.height)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: Theme.hairlineWidth))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .task(id: item.coverURL) { await loadTone() }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var tagLine: some View {
        let tags = Array((details?.tags ?? []).prefix(3))
        if !tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(Theme.Typography.caption)
                        .foregroundColor(tag == "18+" ? .white : Color.white.opacity(0.85))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tag == "18+" ? Theme.Palette.adultTag : Color.white.opacity(0.12)))
                }
            }
            .transition(.opacity)
        }
    }

    private var statusText: String? {
        switch details?.status {
        case .ongoing?: return "连载中"
        case .completed?: return "已完结"
        default: return nil
        }
    }

    private func loadTone() async {
        guard let url = item.coverURL else { return }
        if let cached = CoverColorExtractor.shared.cachedColor(for: url) {
            tone = cached
            return
        }
        guard let color = await CoverColorExtractor.shared.color(for: url), !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.4)) { tone = color }
    }
}
