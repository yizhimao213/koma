import SwiftUI
import KomaCore

/// Reader overlay: top bar (back + titles) and bottom panel (page slider, chapters, mode, brightness).
struct ReaderMenuView: View {
    @Environment(\.accentColor) private var accent
    @ObservedObject var model: ReaderViewModel
    @ObservedObject var pageState: ReaderPageState
    let onClose: () -> Void

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    init(model: ReaderViewModel, pageState: ReaderPageState, onClose: @escaping () -> Void) {
        self.model = model
        self.pageState = pageState
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.menuVisible {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if model.menuVisible {
                bottomPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundColor(.white)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            VStack(alignment: .leading, spacing: 2) {
                Text(pageState.chapter?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text(model.manga.title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 18) {
            pageRow
            modePicker
            brightnessRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
    }

    private var isRTL: Bool { model.mode == .rightToLeft }

    private var displayedPage: Int {
        isScrubbing ? Int(scrubValue) : pageState.page
    }

    /// Previous chapter, slider, next chapter — mirrored as a whole in right-to-left mode.
    private var pageRow: some View {
        HStack(spacing: 14) {
            chapterButton(model.previousChapter, systemImage: "backward.end.fill")
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : Double(pageState.page) },
                        set: { newValue in
                            let rounded = newValue.rounded()
                            scrubValue = rounded
                            model.seek(toPage: Int(rounded))
                        }),
                    in: 0...Double(max(pageState.count - 1, 1)),
                    step: 1,
                    onEditingChanged: { editing in
                        if editing {
                            scrubValue = Double(pageState.page)
                        } else {
                            model.endSeeking()
                            Theme.haptic()
                        }
                        isScrubbing = editing
                    })
                    .tint(accent)
                    .disabled(pageState.count <= 1)
                Text(pageState.count > 0 ? "\(displayedPage + 1) / \(pageState.count)" : " ")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))
                    .environment(\.layoutDirection, .leftToRight)
            }
            chapterButton(model.nextChapter, systemImage: "forward.end.fill")
        }
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
    }

    private func chapterButton(_ chapter: Chapter?, systemImage: String) -> some View {
        Button {
            guard let chapter else { return }
            Theme.haptic()
            model.goTo(chapter: chapter)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .flipsForRightToLeftLayoutDirection(true)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(chapter == nil)
        .opacity(chapter == nil ? 0.35 : 1)
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(ReadingMode.allCases, id: \.self) { mode in
                let selected = model.mode == mode
                Button {
                    Theme.haptic()
                    model.setMode(mode)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: Self.icon(for: mode))
                            .font(.system(size: 18))
                        Text(Self.label(for: mode))
                            .font(.caption2)
                    }
                    .foregroundColor(selected ? accent : .white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? accent.opacity(0.18) : Color.white.opacity(0.06)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private var brightnessRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min")
                .foregroundColor(.white.opacity(0.7))
            Slider(
                value: Binding(
                    get: { Double(model.brightness) },
                    set: { model.setBrightness(CGFloat($0)) }),
                in: 0...1)
                .tint(.white)
            Image(systemName: "sun.max")
                .foregroundColor(.white.opacity(0.7))
        }
    }

    static func icon(for mode: ReadingMode) -> String {
        switch mode {
        case .leftToRight: return "arrow.right.square"
        case .rightToLeft: return "arrow.left.square"
        case .vertical: return "arrow.down.square"
        case .webtoon: return "scroll"
        }
    }

    static func label(for mode: ReadingMode) -> String {
        switch mode {
        case .leftToRight: return "从左到右"
        case .rightToLeft: return "从右到左"
        case .vertical: return "纵向翻页"
        case .webtoon: return "条漫"
        }
    }
}
