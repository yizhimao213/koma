# Koma M2 — MangaDex, 18+, China Network Resilience & Premium UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Koma usable out of the box: a built-in MangaDex source (with 18+ toggle), global search, a Discover page, library update checks, network resilience for mainland-China users, and the approved premium dark visual redesign.

**Architecture:** Networking, MangaDex parsing, library updating, browse caching and connectivity probing are pure KomaCore code behind an injectable `HTTPClient`, unit-tested with stubs on CI. The app layer adds settings, the redesigned SwiftUI screens, cover-color extraction and reader image fallback.

**Tech Stack:** Swift 5 mode, SwiftUI (iOS 16), UIKit reader, GRDB 6, Nuke 12, URLSession, Network.framework (NWPathMonitor), CoreImage (CIAreaAverage), XCTest, GitHub Actions macos-15.

**Spec:** `docs/superpowers/specs/2026-11-18-comic-reader-design.md` — §5.2 (sources, 18+ content), §5.3/§5.4, §5.6.1 (premium visual direction), §5.6.2 (China network), §7 M2.

## Global Constraints

- iOS 16.0 deployment target; no iOS 17-only APIs; `ObservableObject` state; Swift 5 language mode; App target must build with **zero warnings**.
- MangaDex defaults: API `https://api.mangadex.org`, uploads `https://uploads.mangadex.org`, page size **30**, chapter feed page size **500**, cover thumbnail suffix `.512.jpg`.
- Content rating: 18+ off → `contentRating[]=safe&contentRating[]=suggestive`; 18+ on → also `erotica`, `pornographic`. 18+ toggle default **off**, first enable requires confirming "我已年满 18 岁".
- Language priority default: `["zh", "zh-hk", "en"]`.
- Network: API timeout **10 s**, retry **2** times with backoff **0.5 s, 1.0 s** on URLError / HTTP 429 / 5xx; global rate limit **5 requests/second**; User-Agent `Koma/0.2 (iOS)`. Never bypass the system proxy.
- Images: page load timeout **8 s**, fallback host retry up to **2** times; network sources prefetch **2 before / 8 after**; data-saver uses `data-saver` path.
- Data saver setting: `auto` (default; on when `NWPath.isExpensive`), `on`, `off`.
- Visual tokens (dark): background `#0D0D10`, card `#17171C`, elevated `#1C1C22`, hairline `#24242A`, secondary text `#8A8A94`, muted `#5A5A62`; default appearance **dark** (light still supported); large title 28 pt semibold, body 15 pt, caption 12 pt; press scale **0.97**; accent from settings (default `#FF6F61`); 18+ tag red `#FF5A5F`.
- UI strings Simplified Chinese; code/comments/commits English.
- No third-party piracy site scrapers anywhere.
- No local Xcode: tests and builds are verified on GitHub Actions.

## Review Focus

1. **Slow or blocked network (mainland China)** — every remote screen shows cached content or a skeleton immediately, then an inline "加载失败 · 重试" state; nothing blocks the main thread or spins forever. → tests in Task 1 (timeout/retry), Task 3 (cache), manual in Tasks 6–8.
2. **MangaDex chapter feed quirks** — external-only chapters (`externalUrl` set, 0 pages), duplicate chapter numbers across languages/groups, missing chapter numbers (oneshots) — list is clean, one entry per chapter number by language priority, oneshots kept. → tests in Task 2.
3. **18+ toggle off** — no erotica/pornographic manga appear in popular/latest/search/featured, and the 18+ section is hidden. → tests in Task 2, manual in Task 6.
4. **Image host failure mid-chapter** — a failed page falls back to the uploads host and shows a tappable retry instead of a blank cell. → test in Task 2 (fallback URL), manual in Task 8.
5. **Library refresh with removed chapters upstream** — pruned chapters disappear and unread counts stay correct; local manga never pruned. → tests in Task 3.

---

## File Structure

```
Packages/KomaCore/Sources/KomaCore/
  Network/HTTPClient.swift            HTTPClient protocol, URLSessionHTTPClient (timeout, retry, UA)
  Network/RateLimiter.swift           actor token bucket
  Network/NetworkSettings.swift       NetworkSettings value type
  Network/ConnectivityProbe.swift     latency checks
  MangaDex/MangaDexDTO.swift          Decodable DTOs
  MangaDex/MangaDexSource.swift       MangaSource implementation
  MangaDex/MangaDexRequestBuilder.swift  URL/query construction
  Library/LibraryUpdater.swift        refresh chapters for in-library manga
  Library/BrowseCache.swift           last-page cache per (source, kind)
  Models/MangaModels.swift            (modify) PageRef.fallbackURL
  Database/LibraryRepository.swift    (modify) upsert(..., pruneMissing:)
Packages/KomaCore/Tests/KomaCoreTests/
  HTTPClientTests, RateLimiterTests, MangaDexSourceTests (+ MangaDexFixtures), LibraryUpdaterTests,
  BrowseCacheTests, ConnectivityProbeTests
App/
  Theme/Theme.swift                   (modify) tokens, typography, PressableButtonStyle, fadeInOnAppear
  Components/FloatingTabBar.swift
  Components/CoverColorExtractor.swift
  Components/SectionHeader.swift, HorizontalCoverRow.swift, SkeletonView.swift, RetryView.swift
  RootTabView.swift                   (modify) custom floating tab bar
  Features/Library/*                  (modify) redesign + continue card + pull-to-refresh update
  Features/Discover/DiscoverView.swift, DiscoverViewModel.swift, HeroCarousel.swift
  Features/Discover/SourceListView.swift, GlobalSearchView.swift, GlobalSearchViewModel.swift
  Features/Browse/BrowseView.swift    (delete; replaced by Discover)
  Features/Details/*                  (modify) redesign, cache-first load
  Features/Settings/*                 (modify) 内容 / 网络 sections, NetworkSettings provider, path monitor
  AppEnvironment.swift                (modify) register MangaDexSource, updater, cache
  Reader/PageImageLoader.swift        (modify) timeout + fallback + retry state
  Reader/ZoomingPageCell.swift, WebtoonPageCell.swift (modify) failure/retry UI
  Reader/ReaderViewController.swift   (modify) per-source prefetch planner
```

---

### Task 1: Networking core (HTTP client, retry, rate limit)

**Files:** Create `Network/HTTPClient.swift`, `Network/RateLimiter.swift`, `Network/NetworkSettings.swift`; Test `HTTPClientTests.swift`, `RateLimiterTests.swift`.

**Interfaces — Produces:**
- `public protocol HTTPClient: Sendable { func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) }`
- `public struct HTTPError: Error, Equatable { public let statusCode: Int }`
- `public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable { public init(session: URLSession = .shared, limiter: RateLimiter = RateLimiter(ratePerSecond: 5), maxRetries: Int = 2, backoff: [Double] = [0.5, 1.0], timeout: TimeInterval = 10, sleep: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1e9)) }, transport: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil) }` — sets `User-Agent: Koma/0.2 (iOS)` and `timeoutInterval`; retries on `URLError`, 429, 5xx; non-2xx after retries → `HTTPError`. `transport` overrides `session.data(for:)` for tests.
- `public actor RateLimiter { public init(ratePerSecond: Int, now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }, sleep: ...); public func acquire() async }` — token bucket, capacity = rate.
- `public struct NetworkSettings: Sendable, Equatable { apiBaseURL: URL; uploadsBaseURL: URL; usesCustomUploads: Bool; dataSaver: Bool; languages: [String]; showAdult: Bool; static let `default` }` (default values from Global Constraints; `usesCustomUploads` false).

- [ ] **Step 1: Write failing tests:**
  - `testSetsUserAgentAndTimeout`: transport captures request → header `User-Agent == "Koma/0.2 (iOS)"`, `timeoutInterval == 10`.
  - `testRetriesOn503ThenSucceeds`: transport returns 503, 503, 200 → succeeds; 3 calls; sleeps recorded `[0.5, 1.0]`.
  - `testGivesUpAfterRetries`: always 500 → throws `HTTPError(statusCode: 500)`; 3 calls.
  - `testRetriesOnURLError`: `URLError(.timedOut)` once then 200 → succeeds.
  - `testDoesNotRetry404`: 404 → throws `HTTPError(404)` after 1 call.
  - `testRateLimiterSpacesBursts`: fake clock; 7 `acquire()` calls at t=0 with rate 5 → the 6th and 7th incur sleeps totalling ≥ 0.4 s (0.2 s per token).
- [ ] **Step 2:** Push; CI fails. **Step 3:** Implement. **Step 4:** Push; CI green.
- [ ] **Step 5:** Commit `feat(core): add HTTP client with retry, timeout and rate limiting`.

---

### Task 2: MangaDex source

**Files:** Create `MangaDex/MangaDexDTO.swift`, `MangaDex/MangaDexRequestBuilder.swift`, `MangaDex/MangaDexSource.swift`; Modify `Models/MangaModels.swift` (add `public var fallbackURL: URL?` to `PageRef`, init param default `nil`, Codable-compatible); Test `MangaDexSourceTests.swift`, `MangaDexFixtures.swift` (hand-written JSON strings shaped like real API responses).

**Interfaces — Consumes:** `HTTPClient`, `NetworkSettings` (Task 1), `MangaSource`, models.
**Produces:** `public final class MangaDexSource: MangaSource, @unchecked Sendable { public init(client: HTTPClient, settings: @escaping @Sendable () -> NetworkSettings); id = "mangadex"; name = "MangaDex"; language = "multi"; public func featured() async throws -> [MangaRef]; public func adultPicks(page: Int) async throws -> MangaPage }`.

Behavior (exact):
- `popular` → `GET {api}/manga?limit=30&offset=(page-1)*30&includes[]=cover_art&order[followedCount]=desc&hasAvailableChapters=true` + `availableTranslatedLanguage[]` for each language + content ratings. `latest` same with `order[latestUploadedChapter]=desc`. `featured` = `popular(page:1)` first 8. `adultPicks` = popular ordering with ratings `erotica,pornographic` only; throws `SourceError.unsupported` when `showAdult` is false. `search` adds `title=<query>`; filter key `"status"` maps to `status[]=`.
- `hasNextPage = offset + limit < total`.
- Title: first of `attributes.title` / `altTitles` in priority `zh, zh-hk, en, ja-ro, ja`, else any. Cover: `{uploads}/covers/{mangaId}/{fileName}.512.jpg` from the `cover_art` relationship.
- `details` → `GET {api}/manga/{id}?includes[]=author&includes[]=cover_art`; description `zh`→`zh-hk`→`en`; tags = tag names (`zh` else `en`); append `"18+"` tag when `contentRating` is `erotica` or `pornographic`; status `ongoing/completed` else `.unknown`; author from `author` relationship `attributes.name`.
- `chapters` → paginate `GET {api}/manga/{id}/feed?limit=500&offset=…&translatedLanguage[]=…&order[volume]=asc&order[chapter]=asc&includes[]=scanlation_group&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic` until `offset+limit >= total`. Drop items with non-null `externalUrl` or `pages == 0`. Group by `chapter` string (nil = oneshot, keep each oneshot by id); within a group keep the one whose language ranks highest in priority, tie → earliest `publishAt`. Sort by `Double(chapter)` (nil last, stable), assign `index` 0…. Title: `"第 \(n) 话"` (n trimmed, e.g. `12`, `12.5`) or `"番外"` for nil, plus `" · \(title)"` when title non-empty. `Chapter.id` = MangaDex chapter id.
- `pages` → `GET {api}/at-home/server/{chapterId}` → `baseUrl`, `chapter.hash`, `chapter.data` / `dataSaver`. Path segment `data` or `data-saver` by `settings.dataSaver`. Primary URL `{baseUrl}/{seg}/{hash}/{file}` unless `usesCustomUploads` → primary uses `{uploads}/{seg}/{hash}/{file}`. `fallbackURL` = `{uploads}/{seg}/{hash}/{file}` (nil when equal to primary).

- [ ] **Step 1: Write failing tests** (stub `HTTPClient` records requests and returns fixture JSON by path):
  - `testPopularQueryWithoutAdult` (RF3): query has `contentRating[]` = `[safe, suggestive]` only, `availableTranslatedLanguage[]` = `[zh, zh-hk, en]`, `offset=30` for page 2, `order[followedCount]=desc`.
  - `testPopularQueryWithAdult`: four ratings.
  - `testAdultPicksThrowsWhenDisabled` and `testAdultPicksQueryOnlyAdultRatings`.
  - `testParsesTitlePreferringChinese`: fixture with `en` title and `zh` altTitle → title is the zh one; cover URL `https://uploads.mangadex.org/covers/<id>/<file>.512.jpg`.
  - `testHasNextPage`: total 61, page 2 → true; page 3 → false.
  - `testDetailsAdds18PlusTag` (erotica) and description language fallback.
  - `testChaptersDropExternalAndEmpty` (RF2), `testChaptersDedupeByLanguagePriority` (zh beats en for same chapter "5"), `testChaptersKeepOneshots`, `testChaptersSortedAndIndexed` (["10","2","2.5",nil] → 2, 2.5, 10, 番外; titles `第 2 话 · …`), `testChaptersPaginates` (total 600 → two requests, offsets 0 and 500).
  - `testPagesDataAndFallback` (RF4): primary `{baseUrl}/data/{hash}/{f}`, fallback `https://uploads.mangadex.org/data/{hash}/{f}`; `testPagesDataSaver` uses `data-saver` + `dataSaver` file list; `testPagesCustomUploads` primary = custom uploads host, fallback nil.
  - `testCustomAPIBase`: settings with `https://md.example.com` → requests go to that host.
- [ ] **Step 2:** Push; CI fails. **Step 3:** Implement (DTOs with `Decodable`, unknown fields ignored, relationships as `[Relationship]` with `type`, `id`, optional `attributes`). **Step 4:** Push; CI green.
- [ ] **Step 5:** Commit `feat(core): add MangaDex source with content rating and mirror support`.

---

### Task 3: Library updater, chapter pruning, browse cache, connectivity probe

**Files:** Create `Library/LibraryUpdater.swift`, `Library/BrowseCache.swift`, `Network/ConnectivityProbe.swift`; Modify `Database/LibraryRepository.swift`; Test `LibraryUpdaterTests.swift`, `BrowseCacheTests.swift`, `ConnectivityProbeTests.swift`, extend `LibraryRepositoryTests.swift`.

**Produces:**
- `LibraryRepository.upsert(details: MangaDetails, chapters: [Chapter], pruneMissing: Bool = false) throws` — when true, deletes `chapter` rows of that manga whose id is not in `chapters` (inside the same transaction).
- `LibraryRepository.libraryRefs() throws -> [MangaRef]` (all in-library).
- `public struct LibraryUpdateResult: Equatable { updatedMangaCount: Int; newChapterCount: Int; failedCount: Int }`
- `public final class LibraryUpdater: @unchecked Sendable { init(library: LibraryRepository, sources: SourceRegistry, maxConcurrent: Int = 3); func refreshAll() async -> LibraryUpdateResult }` — skips `sourceId == "local"`; per manga: `details` + `chapters` → `upsert(pruneMissing: true)`; new = ids not previously present; errors counted, never thrown.
- `public final class BrowseCache: @unchecked Sendable { init(directory: URL); func store(_ page: MangaPage, sourceId: String, kind: String); func load(sourceId: String, kind: String) -> MangaPage? }` — JSON files; `MangaPage` gains `Codable`.
- `public struct ProbeResult: Equatable { name: String; latencyMs: Int?; error: String? }`; `public struct ConnectivityProbe { init(client: HTTPClient, settings: NetworkSettings, now: @escaping () -> Double); func run() async -> [ProbeResult] }` — `GET {api}/ping` named `"API"`, `GET {uploads}/` named `"图片服务器"` (any HTTP response counts as reachable).

- [ ] **Step 1: Write failing tests:**
  - `testUpsertPruneMissing` (RF5): 3 chapters, re-upsert with 2 + prune → `chapters(for:)` has 2, unread count 2.
  - `testUpsertWithoutPruneKeeps`.
  - `testUpdaterCountsNewChapters`: stub source returns +2 chapters → result `(1, 2, 0)`.
  - `testUpdaterSkipsLocal` (RF5): local manga in library untouched, stub never called for it.
  - `testUpdaterCountsFailures`: throwing source → `failedCount == 1`, no throw.
  - `testBrowseCacheRoundTrip`, `testBrowseCacheMissReturnsNil`.
  - `testProbeReportsLatency` (fake clock 0 → 0.123 → `123`), `testProbeReportsError` (client throws → latency nil, error non-nil).
- [ ] **Step 2:** Push; CI fails. **Step 3:** Implement. **Step 4:** Push; CI green.
- [ ] **Step 5:** Commit `feat(core): add library updater, chapter pruning, browse cache and connectivity probe`.

---

### Task 4: Settings — content (18+) and network; register MangaDex

**Files:** Modify `App/Features/Settings/{AppSettings,SettingsView}.swift`, `App/AppEnvironment.swift`; Create `App/Features/Settings/NetworkPathMonitor.swift`.

**Interfaces — Produces:**
- AppSettings `@AppStorage` keys: `showAdult` (false), `apiBaseURL` (""= default), `uploadsBaseURL` (""= default), `dataSaverMode` (`auto|on|off`, default `auto`), `languagePriority` (comma list, default `zh,zh-hk,en`); `appearance` default changes to `dark`.
- `static func currentNetworkSettings(isExpensive: Bool) -> NetworkSettings` (reads UserDefaults; invalid URLs fall back to defaults).
- `final class NetworkPathMonitor: ObservableObject { @Published private(set) var isExpensive: Bool }` (NWPathMonitor on a background queue, published on main) plus a thread-safe `static var isExpensiveSnapshot` used by the settings closure.
- `AppEnvironment` registers `[LocalSource, MangaDexSource(client: URLSessionHTTPClient(), settings: { AppSettings.currentNetworkSettings(isExpensive: NetworkPathMonitor.isExpensiveSnapshot) })]`, plus `updater: LibraryUpdater`, `browseCache: BrowseCache` (Caches/browse).

- [ ] **Step 1:** Settings sections: **内容** — 显示 18+ 内容 toggle; turning on shows an alert "确认你已年满 18 岁" with 取消 / "我已年满 18 岁"; cancel reverts. **网络** — API 地址 / 图片地址 text fields (placeholder = default URL, validated on submit; invalid → inline red "地址格式不正确"), 省流模式 picker (自动 / 开 / 关), 章节语言优先级 (reorderable list of 简体中文/繁體中文/English/日本語 with toggles), **测试连接** button running `ConnectivityProbe` and listing `API 123 ms` / `图片服务器 失败`.
- [ ] **Step 2:** Push; CI build green, zero App warnings.
- [ ] **Step 3: Verify on device:** toggling 18+ asks once and persists; custom API address takes effect on next request; test connection shows latencies.
- [ ] **Step 4:** Commit `feat(app): content and network settings, register MangaDex source`.

---

### Task 5: Design system, floating tab bar, library redesign

**Files:** Modify `App/Theme/Theme.swift`, `App/RootTabView.swift`, `App/Features/Library/{LibraryView,LibraryViewModel}.swift`, `App/Components/{EmptyStateView,CoverImageView}.swift`; Create `App/Components/{FloatingTabBar,SectionHeader,SkeletonView,RetryView}.swift`.

**Interfaces — Produces:** `Theme.Palette` (adaptive colors from Global Constraints for dark, sensible light equivalents), `Theme.Typography` (`largeTitle`, `title`, `body`, `caption` Fonts), `PressableButtonStyle` (scale 0.97 with Theme.spring), `View.fadeInOnAppear()`, `FloatingTabBar(selection: Binding<AppTab>)` with `enum AppTab: CaseIterable { library, discover, history, downloads, settings }` (labels 书架 发现 历史 下载 设置), `SkeletonView(shape:)` shimmer placeholder, `RetryView(message: String, retry: () -> Void)` ("加载失败" + "重试"), `SectionHeader(title:, actionTitle: "全部", action:)`. Cached `UIImpactFeedbackGenerator` in `Theme.haptic` (deferred minor M10).

- [ ] **Step 1:** RootTabView keeps `TabView(selection:)` for state preservation, hides the system bar (`.toolbar(.hidden, for: .tabBar)`) and overlays `FloatingTabBar` (capsule, `#1C1C22`, hairline border, selected icon = accent, 40 pt high, 12 pt side insets, safe-area aware); content gets bottom inset so grids aren't covered. Hidden while the library detail overlay or reader is shown.
- [ ] **Step 2:** Library per spec §5.6.1: large title "书架" with search + import icons, inverted selected chip, **继续阅读** card (most recent history entry: cover, "继续阅读", "<title> · <chapter>", progress bar `pageIndex+1 / pageCount`, play icon → opens reader directly), 3-column grid (default), accent unread badges, cover decode size from column count (deferred minor M1), pull-to-refresh calls `env.updater.refreshAll()` and toasts "<n> 部漫画有更新" / "已是最新" / "<k> 部更新失败".
- [ ] **Step 3:** Push; CI build green, zero App warnings.
- [ ] **Step 4: Verify on device:** dark default; tab bar floats and switches tabs without losing scroll position; continue card resumes reading; pull-to-refresh toast.
- [ ] **Step 5:** Commit `feat(app): premium design system, floating tab bar and library redesign`.

---

### Task 6: Discover page, source list, global search

**Files:** Create `App/Features/Discover/{DiscoverView,DiscoverViewModel,HeroCarousel,SourceListView,GlobalSearchView,GlobalSearchViewModel}.swift`, `App/Components/{CoverColorExtractor,HorizontalCoverRow}.swift`; Delete `App/Features/Browse/BrowseView.swift`; Modify `RootTabView.swift`.

**Interfaces — Produces:**
- `final class CoverColorExtractor { static let shared; func color(for url: URL) async -> Color? }` — loads via Nuke (thumbnail), CIAreaAverage on a 32×32 downsample off main, darkens to luminance ≤ 0.25 for backgrounds, `NSCache` keyed by URL.
- `DiscoverViewModel` (MainActor ObservableObject): `featured`, `popular`, `latest`, `adult` rows; each row loads from `BrowseCache` first, then network, storing back; per-row state `.loading / .loaded / .failed(String)`; adult row only when `showAdult`.
- `SourceListView(source: MangaSource, initialKind: Kind)` with segmented 热门/最新(/18+), 3-col grid, infinite scroll (load next when last 6 items appear, guard concurrent loads, stop at `hasNextPage == false`), pagination preserved on re-appear (deferred minor M6).
- `GlobalSearchViewModel`: debounce 400 ms, cancels in-flight search on new input, searches all registered sources concurrently, results grouped by source (horizontal rows), per-source failure shown inline.

- [ ] **Step 1:** Discover layout per spec §5.6.1: large title "发现" + search field (tapping opens `GlobalSearchView`), `HeroCarousel` (full-width 220 pt, featured items, background = extracted cover color, cover at right, title / tags / "第 N 话" text at left, auto-advance every 5 s, pauses while dragging, page indicator capsules), rows 热门连载 / 最近更新 / 18+ 精选 with `SectionHeader` → `SourceListView`; bottom section "漫画源" listing registered sources (本地漫画 opens its list). Skeletons while loading; `RetryView` on failure (RF1).
- [ ] **Step 2:** Push; CI build green, zero App warnings.
- [ ] **Step 3: Verify on device:** Discover loads on first launch, carousel animates smoothly, 18+ row appears only when enabled (RF3), global search returns MangaDex results grouped, airplane mode shows cached rows + retry (RF1).
- [ ] **Step 4:** Commit `feat(app): discover page, source lists and global search`.

---

### Task 7: Detail page redesign with cache-first remote loading

**Files:** Modify `App/Features/Details/{MangaDetailView,MangaDetailViewModel}.swift`.

**Interfaces — Consumes:** `CoverColorExtractor`, `LibraryRepository` (chapters/readChapterIds/isInLibrary/upsert), `HistoryRepository.progress`, source `details/chapters`.

- [ ] **Step 1:** Load order: show DB cached details/chapters instantly (if any) → fetch from source in background → upsert (prune only when in library) → publish; network failure with cached data → small inline banner "网络不佳，显示的是缓存内容" + retry; without cache → `RetryView` (RF1).
- [ ] **Step 2:** Visual per spec §5.6.1: ambient background from cover color (top 260 pt fading into `#0D0D10`), centered cover with matched-geometry from library, title / "作者 · 状态 · N 话", tag capsules (18+ red), one primary button "继续阅读 第 X 话 · 第 Y 页" or "开始阅读", bookmark toolbar icon for add/remove library with haptic, collapsible description, chapter rows: "新" (accent) for unread chapters after the progress chapter, `8/24` for the in-progress chapter, dimmed "已读"; long chapter lists use `LazyVStack`; sort toggle; fix double top gap when pushed (deferred minor M7).
- [ ] **Step 3:** Push; CI build green, zero App warnings.
- [ ] **Step 4: Verify on device:** opening a MangaDex title shows content instantly the second time; 18+ tag shows for adult titles; primary button resumes correctly.
- [ ] **Step 5:** Commit `feat(app): redesigned detail page with cache-first loading`.

---

### Task 8: Reader network resilience

**Files:** Modify `App/Reader/{PageImageLoader,ZoomingPageCell,WebtoonPageCell,ReaderViewController,ImagePipelineConfig}.swift`; Create pure helper `Packages/KomaCore/Sources/KomaCore/Reader/ImageSourcePlan.swift` + `ImageSourcePlanTests.swift`.

**Interfaces — Produces:** `public struct ImageSourcePlan: Equatable { public init(page: PageRef, maxAttempts: Int = 3); public func url(forAttempt n: Int) -> URL? }` — attempt 0 = primary, 1 = fallback (or primary again if none), 2 = fallback again (or primary), ≥ maxAttempts → nil.

- [ ] **Step 1: Write failing tests:** `testPlanWithFallback` (0 → primary, 1 → fallback, 2 → fallback, 3 → nil), `testPlanWithoutFallback` (0,1,2 → primary, 3 → nil).
- [ ] **Step 2:** Push; CI fails. **Step 3:** Implement plan; `PageImageLoader` applies an 8 s timeout per attempt (`ImageRequest` with `URLRequest.timeoutInterval = 8`) and walks the plan; cells show a centered spinner while loading and, after exhaustion, a "加载失败 · 点击重试" view (tap restarts the plan) instead of a blank cell (RF4). ReaderViewController uses `PrefetchPlanner(before: 2, after: 8)` when `manga.sourceId != "local"`. Local file URLs skip the Nuke disk cache (deferred Task 7 note: avoid copying local files into the 1 GB cache) via `ImageRequest.Options.disableDiskCache`.
- [ ] **Step 4:** Push; CI green, zero App warnings.
- [ ] **Step 5: Verify on device:** reading a MangaDex chapter on cellular uses data-saver images; toggling airplane mode mid-chapter shows retry cells that recover after reconnecting.
- [ ] **Step 6:** Commit `feat(app): resilient reader image loading with fallback and retry`; tag `v0.2.0` after the final review.
