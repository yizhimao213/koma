import Combine
import UIKit
import Nuke
import KomaCore

@MainActor
protocol ReaderViewControllerDelegate: AnyObject {
    var readerMenuVisible: Bool { get }
    func readerSetMenuVisible(_ visible: Bool)
    /// The item at the center of the viewport changed.
    func readerDidShow(index: Int)
}

/// One collection view for every reading mode:
/// - leftToRight / rightToLeft: horizontal paging (RTL via `.forceRightToLeft`, the flow layout flips itself)
/// - vertical: vertical paging
/// - webtoon: continuous vertical strip, cell height = width × image aspect, zoomed by scaling the
///   collection view (transform about its center, pans via contentOffset vertically and translation horizontally).
final class ReaderViewController: UIViewController, UICollectionViewDelegateFlowLayout,
    UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {

    weak var delegate: ReaderViewControllerDelegate?

    private let session: ReaderSession
    private(set) var mode: ReadingMode
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, ReaderItem>!
    /// Mirror of the applied snapshot (sizes are looked up synchronously during layout).
    private var items: [ReaderItem] = []
    private var cancellables = Set<AnyCancellable>()

    private let planner = PrefetchPlanner()
    private let tapResolver = TapZoneResolver()
    private let prefetcher = ImagePrefetcher(pipeline: ImagePipeline.shared, destination: .memoryCache, maxConcurrentRequestCount: 3)
    private var prefetchedRequests: [ReaderItem: ImageRequest] = [:]

    /// Known height / width ratios, shared by all modes.
    private var aspects: [ReaderItem: CGFloat] = [:]
    private var pendingAspects: [ReaderItem: CGFloat] = [:]
    private var aspectFlushScheduled = false
    private var aspectProbes: [ReaderItem: ImageTask] = [:]

    private var reportedIndex: Int?
    private var pendingScrollIndex: Int?
    private var scrollTargetIndex: Int?
    private var isRepositioning = false
    private var lastViewSize: CGSize = .zero

    // Webtoon zoom
    private var zoomScale: CGFloat = 1
    private var zoomTranslationX: CGFloat = 0
    private var lastPinchLocation: CGPoint = .zero

    private lazy var singleTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        gesture.delegate = self
        return gesture
    }()

    private lazy var webtoonDoubleTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleWebtoonDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        gesture.delegate = self
        return gesture
    }()

    private lazy var pinch: UIPinchGestureRecognizer = {
        let gesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        gesture.delegate = self
        return gesture
    }()

    private lazy var horizontalPan: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleHorizontalPan(_:)))
        gesture.maximumNumberOfTouches = 1
        gesture.delegate = self
        return gesture
    }()

    init(session: ReaderSession, mode: ReadingMode) {
        self.session = session
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .black
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.scrollsToTop = false
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true
        view.addSubview(collectionView)

        configureDataSource()

        view.addGestureRecognizer(singleTap)
        view.addGestureRecognizer(webtoonDoubleTap)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(horizontalPan)

        applyModeSettings()

        session.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncItems() }
            .store(in: &cancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        if size != lastViewSize {
            lastViewSize = size
            let anchor = pendingScrollIndex ?? reportedIndex
            resetWebtoonZoom(animated: false)
            collectionView.frame = view.bounds
            collectionView.collectionViewLayout.invalidateLayout()
            stopAllPrefetching()
            if let anchor { pendingScrollIndex = anchor }
        }
        performPendingScroll()
    }

    // MARK: - Data

    private func configureDataSource() {
        let pageRegistration = UICollectionView.CellRegistration<ZoomingPageCell, ReaderItem> { [weak self] cell, _, item in
            guard let self, case .page(_, let page) = item else { return }
            cell.onAspect = { [weak self] aspect in self?.recordAspect(aspect, for: item) }
            cell.configure(request: self.request(for: page))
        }
        let webtoonRegistration = UICollectionView.CellRegistration<WebtoonPageCell, ReaderItem> { [weak self] cell, _, item in
            guard let self, case .page(_, let page) = item else { return }
            cell.onAspect = { [weak self] aspect in self?.recordAspect(aspect, for: item) }
            cell.configure(request: self.request(for: page))
        }
        let transitionRegistration = UICollectionView.CellRegistration<TransitionPageCell, ReaderItem> { cell, _, item in
            guard case .transition(let from, let to) = item else { return }
            cell.configure(from: from, to: to)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, ReaderItem>(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            switch item {
            case .transition:
                return collectionView.dequeueConfiguredReusableCell(using: transitionRegistration, for: indexPath, item: item)
            case .page:
                if self?.mode == .webtoon {
                    return collectionView.dequeueConfiguredReusableCell(using: webtoonRegistration, for: indexPath, item: item)
                }
                return collectionView.dequeueConfiguredReusableCell(using: pageRegistration, for: indexPath, item: item)
            }
        }
    }

    private func makeSnapshot(_ items: [ReaderItem]) -> NSDiffableDataSourceSnapshot<Int, ReaderItem> {
        var snapshot = NSDiffableDataSourceSnapshot<Int, ReaderItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(items)
        return snapshot
    }

    /// Applies the session's items: appends (next chapter preloaded) keep the visible page exactly in place;
    /// anything else (start, chapter jump) reloads and scrolls to the session's current index.
    private func syncItems() {
        let newItems = session.items
        guard newItems != items else { return }
        let isAppend = !items.isEmpty && newItems.count > items.count
            && Array(newItems.prefix(items.count)) == items
        if isAppend {
            let anchor = visibleAnchor()
            items = newItems
            isRepositioning = true
            dataSource.apply(makeSnapshot(newItems), animatingDifferences: false)
            collectionView.layoutIfNeeded()
            if let anchor { restore(anchor) }
            isRepositioning = false
            if let index = reportedIndex { updatePrefetch(around: index) }
        } else {
            items = newItems
            reportedIndex = nil
            scrollTargetIndex = nil
            stopAllPrefetching()
            resetWebtoonZoom(animated: false)
            pendingScrollIndex = newItems.isEmpty ? nil : min(session.currentIndex, newItems.count - 1)
            dataSource.applySnapshotUsingReloadData(makeSnapshot(newItems))
            performPendingScroll()
        }
    }

    private struct Anchor {
        let item: ReaderItem
        let offset: CGPoint
    }

    /// The centered item and the content offset relative to its origin.
    private func visibleAnchor() -> Anchor? {
        guard let indexPath = centerIndexPath(), items.indices.contains(indexPath.item),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
        let offset = collectionView.contentOffset
        return Anchor(
            item: items[indexPath.item],
            offset: CGPoint(x: offset.x - attributes.frame.minX, y: offset.y - attributes.frame.minY))
    }

    private func restore(_ anchor: Anchor) {
        guard let indexPath = dataSource.indexPath(for: anchor.item),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }
        let target = CGPoint(x: attributes.frame.minX + anchor.offset.x, y: attributes.frame.minY + anchor.offset.y)
        let current = collectionView.contentOffset
        if abs(target.x - current.x) > 0.5 || abs(target.y - current.y) > 0.5 {
            collectionView.contentOffset = target
        }
    }

    private func performPendingScroll() {
        guard let index = pendingScrollIndex, items.indices.contains(index),
              collectionView.bounds.width > 0, collectionView.bounds.height > 0 else { return }
        pendingScrollIndex = nil
        isRepositioning = true
        collectionView.layoutIfNeeded()
        scroll(to: index, animated: false)
        collectionView.layoutIfNeeded()
        isRepositioning = false
        report(index: index)
    }

    // MARK: - Mode

    func setMode(_ newMode: ReadingMode) {
        guard newMode != mode, isViewLoaded else {
            mode = newMode
            return
        }
        let anchorIndex = centerIndexPath()?.item ?? reportedIndex ?? session.currentIndex
        resetWebtoonZoom(animated: false)
        stopAllPrefetching()
        mode = newMode
        // Cross-fade from a snapshot of the old mode; the switch itself happens without animation.
        let snapshotView = view.snapshotView(afterScreenUpdates: false)
        if let snapshotView {
            snapshotView.frame = view.bounds
            snapshotView.isUserInteractionEnabled = false
            view.addSubview(snapshotView)
        }
        UIView.performWithoutAnimation {
            applyModeSettings()
            collectionView.setCollectionViewLayout(makeLayout(), animated: false)
            reportedIndex = nil
            pendingScrollIndex = items.isEmpty ? nil : min(anchorIndex, items.count - 1)
            dataSource.applySnapshotUsingReloadData(makeSnapshot(items))
            performPendingScroll()
        }
        if let snapshotView {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: {
                snapshotView.alpha = 0
            }, completion: { _ in
                snapshotView.removeFromSuperview()
            })
        }
    }

    private func makeLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = (mode == .leftToRight || mode == .rightToLeft) ? .horizontal : .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        return layout
    }

    private func applyModeSettings() {
        let isWebtoon = mode == .webtoon
        collectionView.semanticContentAttribute = mode == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        collectionView.isPagingEnabled = !isWebtoon
        collectionView.decelerationRate = .normal
        collectionView.alwaysBounceHorizontal = mode == .leftToRight || mode == .rightToLeft
        collectionView.alwaysBounceVertical = !collectionView.alwaysBounceHorizontal
        webtoonDoubleTap.isEnabled = isWebtoon
        pinch.isEnabled = isWebtoon
        horizontalPan.isEnabled = isWebtoon
    }

    // MARK: - Navigation

    /// Scrolls to a 0-based page position within a loaded chapter (slider scrubbing).
    func scrollToPage(chapterId: String, position: Int) {
        guard let first = items.firstIndex(where: {
            if case .page(let id, _) = $0 { return id == chapterId }
            return false
        }) else { return }
        let index = first + max(position, 0)
        guard items.indices.contains(index), case .page(let id, _) = items[index], id == chapterId else { return }
        scrollTargetIndex = nil
        scroll(to: index, animated: false)
    }

    private func scroll(to index: Int, animated: Bool) {
        let indexPath = IndexPath(item: index, section: 0)
        switch mode {
        case .leftToRight, .rightToLeft:
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
        case .vertical:
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
        case .webtoon:
            guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }
            let inset = collectionView.contentInset.top
            let target = clampedWebtoonOffset(attributes.frame.minY - inset)
            collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: animated)
        }
    }

    private func clampedWebtoonOffset(_ y: CGFloat) -> CGFloat {
        let inset = collectionView.contentInset.top
        let maxY = max(-inset, collectionView.contentSize.height - collectionView.bounds.height + collectionView.contentInset.bottom)
        return min(max(y, -inset), maxY)
    }

    private func step(_ direction: Int) {
        if mode == .webtoon {
            let distance = collectionView.bounds.height / zoomScale * 0.85
            let target = clampedWebtoonOffset(collectionView.contentOffset.y + CGFloat(direction) * distance)
            collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
            return
        }
        let current = scrollTargetIndex ?? centerIndexPath()?.item ?? reportedIndex ?? 0
        let target = current + direction
        guard items.indices.contains(target) else { return }
        scrollTargetIndex = target
        scroll(to: target, animated: true)
    }

    private func centerIndexPath() -> IndexPath? {
        let bounds = collectionView.bounds
        return collectionView.indexPathForItem(at: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    private func updateCurrentIndex() {
        guard !isRepositioning, pendingScrollIndex == nil, let indexPath = centerIndexPath() else { return }
        if indexPath.item != reportedIndex {
            report(index: indexPath.item)
        }
    }

    private func report(index: Int) {
        reportedIndex = index
        delegate?.readerDidShow(index: index)
        updatePrefetch(around: index)
    }

    // MARK: - Taps

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if delegate?.readerMenuVisible == true {
            delegate?.readerSetMenuVisible(false)
            return
        }
        let action = tapResolver.action(for: gesture.location(in: view), in: view.bounds.size, mode: mode)
        switch action {
        case .toggleMenu:
            delegate?.readerSetMenuVisible(true)
        case .next:
            step(1)
        case .previous:
            step(-1)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Single taps wait for any double tap (the page cells' zoom toggle or the webtoon one).
        guard gestureRecognizer === singleTap,
              let tap = otherGestureRecognizer as? UITapGestureRecognizer else { return false }
        return tap.numberOfTapsRequired == 2
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === pinch || gestureRecognizer === horizontalPan
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === horizontalPan {
            return mode == .webtoon && zoomScale > 1.01
        }
        return true
    }

    // MARK: - Webtoon zoom

    private var zoomState: WebtoonLayoutMath.ZoomState {
        WebtoonLayoutMath.ZoomState(
            scale: zoomScale,
            translationX: zoomTranslationX,
            verticalInset: collectionView.contentInset.top,
            contentOffsetY: collectionView.contentOffset.y)
    }

    private func applyZoom(_ state: WebtoonLayoutMath.ZoomState) {
        zoomScale = state.scale
        zoomTranslationX = state.translationX
        applyZoomTransform()
        let inset = UIEdgeInsets(top: state.verticalInset, left: 0, bottom: state.verticalInset, right: 0)
        if collectionView.contentInset != inset {
            collectionView.contentInset = inset
        }
        collectionView.contentOffset = CGPoint(x: 0, y: state.contentOffsetY)
    }

    private func applyZoomTransform() {
        collectionView.transform = CGAffineTransform(translationX: zoomTranslationX, y: 0)
            .scaledBy(x: zoomScale, y: zoomScale)
    }

    private func resetWebtoonZoom(animated: Bool) {
        guard zoomScale != 1 || zoomTranslationX != 0 || collectionView.contentInset != .zero else { return }
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let anchor = WebtoonLayoutMath.contentPoint(at: center, state: zoomState, viewSize: view.bounds.size)
        let target = WebtoonLayoutMath.zoom(
            scale: 1, anchorContent: anchor, at: center,
            viewSize: view.bounds.size, contentHeight: collectionView.contentSize.height)
        if animated {
            stopScrolling()
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.applyZoom(target)
            }
        } else {
            applyZoom(target)
        }
    }

    /// Stops any deceleration or programmatic scroll animation.
    private func stopScrolling() {
        collectionView.setContentOffset(collectionView.contentOffset, animated: false)
    }

    private func cancel(_ gesture: UIGestureRecognizer) {
        guard gesture.isEnabled else { return }
        gesture.isEnabled = false
        gesture.isEnabled = true
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        let size = view.bounds.size
        switch gesture.state {
        case .began:
            cancel(collectionView.panGestureRecognizer)
            cancel(horizontalPan)
            stopScrolling()
            lastPinchLocation = gesture.location(in: view)
            gesture.scale = 1
        case .changed:
            let location = gesture.location(in: view)
            guard gesture.numberOfTouches >= 2 else {
                lastPinchLocation = location
                return
            }
            let anchor = WebtoonLayoutMath.contentPoint(at: lastPinchLocation, state: zoomState, viewSize: size)
            let state = WebtoonLayoutMath.zoom(
                scale: zoomScale * gesture.scale, anchorContent: anchor, at: location,
                viewSize: size, contentHeight: collectionView.contentSize.height)
            applyZoom(state)
            gesture.scale = 1
            lastPinchLocation = location
        case .ended, .cancelled, .failed:
            if zoomScale < 1.05 {
                resetWebtoonZoom(animated: true)
            }
            updateCurrentIndex()
        default:
            break
        }
    }

    @objc private func handleWebtoonDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard mode == .webtoon else { return }
        if zoomScale > 1.01 {
            resetWebtoonZoom(animated: true)
            return
        }
        stopScrolling()
        let size = view.bounds.size
        let point = gesture.location(in: view)
        let anchor = WebtoonLayoutMath.contentPoint(at: point, state: zoomState, viewSize: size)
        let target = WebtoonLayoutMath.zoom(
            scale: 2, anchorContent: anchor, at: point,
            viewSize: size, contentHeight: collectionView.contentSize.height)
        UIView.animate(
            withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) {
            self.applyZoom(target)
        }
    }

    @objc private func handleHorizontalPan(_ gesture: UIPanGestureRecognizer) {
        let maxTranslation = WebtoonLayoutMath.maxTranslationX(scale: zoomScale, viewWidth: view.bounds.width)
        func clamp(_ value: CGFloat) -> CGFloat { min(max(value, -maxTranslation), maxTranslation) }
        switch gesture.state {
        case .changed:
            let delta = gesture.translation(in: view).x
            gesture.setTranslation(.zero, in: view)
            zoomTranslationX = clamp(zoomTranslationX + delta)
            applyZoomTransform()
        case .ended:
            let target = clamp(zoomTranslationX + gesture.velocity(in: view).x * 0.2)
            UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.zoomTranslationX = target
                self.applyZoomTransform()
            }
        default:
            break
        }
    }

    // MARK: - Webtoon aspect ratios

    private func recordAspect(_ aspect: CGFloat, for item: ReaderItem) {
        guard aspect.isFinite, aspect > 0 else { return }
        if let known = aspects[item], abs(known - aspect) < 0.001 { return }
        guard mode == .webtoon else {
            aspects[item] = aspect
            return
        }
        pendingAspects[item] = aspect
        guard !aspectFlushScheduled else { return }
        aspectFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushAspects()
        }
    }

    /// Applies new aspects in one layout pass. Items whose top is above the viewport shift the content
    /// offset by their height delta so what is on screen does not move.
    private func flushAspects() {
        aspectFlushScheduled = false
        let pending = pendingAspects
        pendingAspects = [:]
        guard !pending.isEmpty else { return }
        guard mode == .webtoon else {
            for (item, aspect) in pending { aspects[item] = aspect }
            return
        }
        let width = collectionView.bounds.width
        var changes: [WebtoonLayoutMath.HeightChange] = []
        for (item, aspect) in pending {
            if let indexPath = dataSource.indexPath(for: item),
               let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
                changes.append(WebtoonLayoutMath.HeightChange(
                    minY: attributes.frame.minY,
                    oldHeight: attributes.frame.height,
                    newHeight: WebtoonLayoutMath.height(forWidth: width, aspect: aspect)))
            }
            aspects[item] = aspect
        }
        let visibleTop = collectionView.contentOffset.y + collectionView.contentInset.top
        let delta = WebtoonLayoutMath.contentOffsetAdjustment(for: changes, visibleTop: visibleTop)
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        if delta != 0 {
            var offset = collectionView.contentOffset
            offset.y += delta
            collectionView.contentOffset = offset
        }
    }

    /// Loads (coalesced with the prefetcher) the upcoming webtoon pages just to learn their aspect ratio
    /// while they are still off screen.
    private func probeAspects(for indices: [Int]) {
        var wanted = Set<ReaderItem>()
        for index in indices {
            let item = items[index]
            guard case .page(_, let page) = item, aspects[item] == nil else { continue }
            wanted.insert(item)
            guard aspectProbes[item] == nil else { continue }
            let request = PageImageRequest.make(for: page, mode: mode, viewSize: collectionView.bounds.size, priority: .low)
            aspectProbes[item] = ImagePipeline.shared.loadImage(with: request) { [weak self] result in
                guard let self else { return }
                self.aspectProbes[item] = nil
                if case .success(let response) = result, response.image.size.width > 0 {
                    self.recordAspect(response.image.size.height / response.image.size.width, for: item)
                }
            }
        }
        for (item, task) in aspectProbes where !wanted.contains(item) {
            task.cancel()
            aspectProbes[item] = nil
        }
    }

    // MARK: - Prefetching

    private func request(for page: PageRef) -> ImageRequest {
        PageImageRequest.make(for: page, mode: mode, viewSize: collectionView.bounds.size, priority: .high)
    }

    private func updatePrefetch(around index: Int) {
        guard collectionView.bounds.width > 0 else { return }
        let indices = planner.indices(around: index, count: items.count)
        var wanted: [ReaderItem: ImageRequest] = [:]
        var ordered: [ImageRequest] = []
        for i in indices {
            let item = items[i]
            guard case .page(_, let page) = item else { continue }
            let request = prefetchedRequests[item] ?? self.request(for: page)
            wanted[item] = request
            if prefetchedRequests[item] == nil { ordered.append(request) }
        }
        let stale = prefetchedRequests.compactMap { wanted[$0.key] == nil ? $0.value : nil }
        if !stale.isEmpty { prefetcher.stopPrefetching(with: stale) }
        if !ordered.isEmpty { prefetcher.startPrefetching(with: ordered) }
        prefetchedRequests = wanted
        if mode == .webtoon {
            probeAspects(for: indices)
        }
    }

    private func stopAllPrefetching() {
        prefetcher.stopPrefetching()
        prefetchedRequests = [:]
        for task in aspectProbes.values { task.cancel() }
        aspectProbes = [:]
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard collectionView.bounds.width > 0 else { return }
        let requests: [ImageRequest] = indexPaths.compactMap { indexPath in
            guard items.indices.contains(indexPath.item),
                  case .page(_, let page) = items[indexPath.item] else { return nil }
            return request(for: page)
        }
        if !requests.isEmpty { prefetcher.startPrefetching(with: requests) }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        // Keep everything inside the planner's window; only drop the rest.
        let requests: [ImageRequest] = indexPaths.compactMap { indexPath in
            guard items.indices.contains(indexPath.item) else { return nil }
            let item = items[indexPath.item]
            guard prefetchedRequests[item] == nil, case .page(_, let page) = item else { return nil }
            return request(for: page)
        }
        if !requests.isEmpty { prefetcher.stopPrefetching(with: requests) }
    }

    // MARK: - UICollectionViewDelegateFlowLayout

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let size = collectionView.bounds.size
        guard mode == .webtoon, items.indices.contains(indexPath.item) else { return size }
        let item = items[indexPath.item]
        switch item {
        case .page:
            return CGSize(width: size.width, height: WebtoonLayoutMath.height(forWidth: size.width, aspect: aspects[item]))
        case .transition:
            return CGSize(width: size.width, height: max(320, size.height * 0.6))
        }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ZoomingPageCell)?.resetZoom()
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCurrentIndex()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollTargetIndex = nil
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentIndex()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scrollTargetIndex = nil
        updateCurrentIndex()
    }
}
