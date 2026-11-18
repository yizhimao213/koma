# iOS 漫画阅读器 — 设计文档

- 日期：2026-11-18
- 状态：待批准
- 工作名：**Koma**（日语"格/分镜"，可随时改名）

## 1. 意图与原因

做一款**自用**的 iOS 漫画阅读 App，通过 TrollStore 安装在用户自己的 iPhone（iOS 16.3.1）上。

用户的核心诉求：

1. **界面非常好看**，一眼就能看明白怎么用。
2. **功能齐全**：书架、发现/搜索、阅读器、历史、下载、设置。
3. **能接入大量漫画源**。
4. **所有操作都要丝滑**：翻页、缩放、滚动、页面切换、图片加载都不能卡顿或闪烁。
5. 通过 TrollStore 安装，**不开启开发者模式**。

## 2. 目标 / 非目标 / 反目标

### 目标
- 原生 iOS 手感，支持 ProMotion 120Hz。
- 可插拔的"源"架构：内置合法源，用户可以自行添加源插件，实现"一个 App 看所有源"。
- 用户在 Windows 上就能完成"改代码 → 云端编译 → 拿到 IPA → TrollStore 安装"的全流程。

### 非目标
- 上架 App Store。
- 账号体系、云同步（用本地备份/恢复替代）。
- 安卓版。
- 针对 iPad 的专门布局（布局自适应即可，不专门打磨）。
- 评论、社交功能。

### 反目标（技术上能跑，但出现以下情况就算失败）
- 阅读器滑动掉帧、图片加载时闪白或跳动。
- 新用户打开 App 后不知道该点哪里。
- 某个源出错导致整个 App 崩溃或卡死。
- App 内置盗版站的爬虫。

## 3. 约束

| 约束 | 影响 |
|---|---|
| iOS 16.3.1 | 部署目标 **iOS 16.0**。不能用 SwiftData、`@Observable`、iOS 17 的 `scrollTransition` 等 API |
| TrollStore 安装 | 产物为**未签名 IPA**（`CODE_SIGNING_ALLOWED=NO`），TrollStore 负责签名。不需要特殊 entitlements，保持标准沙盒 |
| 用户只有 Windows | Xcode 工程用 **XcodeGen**（`project.yml`）生成，不手写 `.xcodeproj`。编译跑在 **GitHub Actions macOS runner** 上 |
| 版权 | App 只内置合法源，第三方源由用户自己添加；仓库里不放任何盗版站的脚本 |

## 4. 方案对比（已决定）

| 方案 | 优点 | 缺点 |
|---|---|---|
| **A. 原生 Swift（SwiftUI + UIKit 阅读器）** ✅ 已选 | 最丝滑，原生 120Hz 和手势，iOS 原汁原味 | 需要 macOS 编译（用 GitHub Actions 解决） |
| B. Flutter | 可以顺带出安卓版 | 手感非原生，iOS 仍需 Mac |
| C. React Native + Expo | 不需要 Mac | 图片密集的阅读器最难保证丝滑 |

**选 A 的原因**：用户最看重的是丝滑，原生是唯一能把手感做满的方案；没有 Mac 的问题用 GitHub Actions 云端编译解决。

## 5. 设计

### 5.1 技术栈

- Swift 5.9+，Xcode 15+（CI 上使用 `macos-14` runner）
- **SwiftUI**：App 外壳、书架、发现、详情、历史、下载、设置
- **UIKit**（`UIViewControllerRepresentable` 嵌入）：阅读器
- **Nuke**（SPM）：图片管线，包括内存/磁盘缓存、预加载、后台解码、按屏幕尺寸降采样
- **GRDB**（SPM）：本地数据库（书架、分类、章节、阅读进度、历史、下载记录）
- **ZIPFoundation**（SPM）：解压 CBZ/ZIP
- **JavaScriptCore**（系统框架）：运行用户添加的源插件
- **SwiftSoup**（SPM）：HTML 解析，暴露给插件使用
- 状态管理：MVVM + `ObservableObject` / `@Published`（适配 iOS 16）

### 5.2 源架构

所有源都实现同一个协议：

```swift
protocol MangaSource {
    var id: String { get }
    var name: String { get }
    var language: String { get }
    var icon: URL? { get }
    func popular(page: Int) async throws -> MangaPage
    func latest(page: Int) async throws -> MangaPage
    func search(query: String, filters: [Filter], page: Int) async throws -> MangaPage
    func details(for manga: MangaRef) async throws -> MangaDetails
    func chapters(for manga: MangaRef) async throws -> [Chapter]
    func pages(for chapter: Chapter) async throws -> [PageRef]   // 图片 URL + 所需请求头
}
```

**内置源（合法）：**

1. **MangaDex**：使用官方公开 API，支持多语言（含中文）。
2. **本地漫画**：通过"文件"App 导入 CBZ / ZIP / PDF / 图片文件夹，也支持从其他 App"分享到 Koma"。
3. **OPDS**：连接用户自建的书库（Komga / Kavita / Calibre-Web），支持填写地址和账号。

**用户插件源（JS）：**

- 用户在「设置 → 源 → 添加仓库」中填写一个仓库 URL，仓库提供 `index.json`（包含插件列表、版本号、脚本地址）。
- 每个插件是一个 JS 文件，导出与上面协议对应的函数，运行在独立的 `JSContext` 里。
- App 向 JS 提供的 API：`fetch(url, options)`（原生 URLSession 实现，支持自定义请求头和 Cookie）、`parseHTML(html)`（基于 SwiftSoup 的选择器查询）、`console.log`、`storage.get/set`（每个插件独立的键值存储）。
- **隔离**：每次调用都有超时（默认 15 秒），JS 异常会被捕获并转成 Swift 错误，界面上只显示"该源暂时不可用"，不影响其他源和 App 本身。
- 插件可以声明自己是否需要 WebView 登录或过盾验证（Cloudflare），需要时 App 弹出内置 `WKWebView`，让用户手动通过验证，然后把 Cookie 共享给 `fetch` 使用。
- 仓库里提供一份**插件开发文档 + 一个示例插件**（以 MangaDex 为例重写一遍），不附带任何第三方站点的插件。

### 5.3 信息架构（5 个底部 Tab）

```
┌──────────────────────────────┐
│  书架   发现   历史   下载   设置 │
└──────────────────────────────┘
```

1. **书架**
   - 封面网格（默认 3 列，可切换为 2 列、4 列或列表），封面右上角显示未读章节数角标。
   - 顶部是分类标签栏（可左右滑动，例如"全部 / 在追 / 已完结 / 自定义"）。
   - 排序：最近阅读、最近更新、名称、未读数。筛选：未读、已下载、已完结。
   - 下拉刷新，检查所有书架漫画的新章节。
   - 长按封面弹出快捷菜单：标记已读、移动分类、下载、移出书架。
2. **发现**
   - 顶部是全局搜索框（同时搜索所有已启用的源，结果按源分组横向展示）。
   - 下方是源列表，点击进入某个源的"热门 / 最新 / 筛选"页面。
3. **历史**：按日期分组（今天 / 昨天 / 更早），每条显示"读到第 X 话第 Y 页"，点击直接续读。
4. **下载**：下载队列（暂停/继续/删除，显示进度），已下载漫画列表，显示占用空间。
5. **设置**：外观、阅读器默认值、源与仓库管理、缓存管理、备份/恢复、关于。

**漫画详情页**
- 顶部是封面大图，背景用封面做高斯模糊；下方是标题、作者、状态、标签。
- 主按钮：**"开始阅读" / "继续阅读 第 X 话"**，以及"加入书架"。
- 简介默认折叠，点击展开。
- 章节列表：已读的章节变灰，支持倒序、多选下载、批量标记已读。

### 5.4 阅读器

- **阅读模式**：从左到右翻页、从右到左翻页（日漫）、竖向翻页、**条漫连续滚动**（webtoon）。可以对每部漫画单独记住设置。
- **手势**：点击左/右区域翻页、点击中间呼出菜单；双指缩放；双击在缩放和适应屏幕之间切换；条漫模式下也可以缩放。
- **菜单**：顶部显示标题、章节名和返回按钮；底部是页码滑块（拖动时显示缩略图预览）、上一话/下一话、阅读模式切换、亮度调节。
- **无缝切章**：读到章节末尾时会出现一个过渡页（"下一话：XXX"），继续翻页会直接进入下一话，下一话的前几页已经提前加载好。
- **适应方式**：适应宽度、适应高度、适应屏幕、原始大小；可选裁切白边。
- 阅读时保持屏幕常亮（可在设置中关闭），每翻一页自动保存进度。

### 5.5 丝滑性能方案

| 手段 | 说明 |
|---|---|
| 开启 120Hz | Info.plist 设置 `CADisableMinimumFrameDurationOnPhone = YES` |
| 阅读器使用 UIKit | `UICollectionView`（翻页用 paging，条漫用连续滚动），每页是一个 `UIScrollView` 负责缩放 |
| 图片后台解码 + 降采样 | Nuke 在后台线程按屏幕像素尺寸解码，主线程只负责显示 |
| 预加载 | 当前页前后各预加载 N 页（默认前 2 后 5），并在章节末尾提前拉取下一话 |
| 占位不跳动 | 先拿到图片尺寸或使用估算比例，固定 cell 高度，避免条漫加载时页面跳动 |
| 渐显 | 图片加载完成后 0.15 秒淡入，不闪白 |
| 共享元素转场 | 书架封面到详情页使用 `matchedGeometryEffect` 做放大过渡 |
| 弹簧动画 + 触感反馈 | 全局使用统一的 spring 参数；翻页到边界、加入书架等操作配合轻微震动 |
| 列表性能 | 书架用 `LazyVGrid`，封面只加载缩略图尺寸；数据库查询放在后台 |
| 性能验收 | 在 Instruments 中检查，条漫快速滑动时没有明显掉帧（目标 ≥ 110fps） |

### 5.6 视觉风格（人家的方案，用户可以改）

- 风格：干净、卡片化、大封面优先，参考 iOS 原生 App 的排版习惯。封面是视觉主角，界面上的装饰尽量少。
- 支持浅色 / 深色 / 跟随系统；**阅读器默认使用纯黑背景**。
- 主题色默认使用一个暖色（例如珊瑚橙），可以在设置中切换。
- 圆角：封面 10pt，卡片 16pt；字体使用系统 SF Pro / 苹方，层级清晰。
- 空状态都配插画和一句引导，例如书架为空时显示："还没有漫画，去「发现」看看吧"，并附带一个跳转按钮。

### 5.7 数据与存储

- **GRDB 表**：`manga`、`chapter`、`category`、`manga_category`、`history`、`download`、`source_repo`、`plugin`。
- 图片缓存使用 Nuke 磁盘缓存（默认上限 1GB，可调整）；已下载章节单独存放在 `Documents/Downloads/<源>/<漫画>/<章节>/`，不受缓存清理影响。
- **备份/恢复**：把书架、分类、进度、源仓库列表导出为一个 JSON 文件，通过分享面板保存。

### 5.8 下载

- 使用后台 `URLSession` 实现，App 切到后台也能继续下载。
- 每个源有并发上限（默认 2），避免请求过多被源站封禁。
- 失败自动重试 3 次，之后标记为失败，用户可以手动重试。

### 5.9 编译与安装流程

1. 代码托管在 GitHub 仓库。
2. `project.yml` 交给 XcodeGen，在 CI 上生成 `.xcodeproj`。
3. GitHub Actions（`macos-14`）：`xcodegen` → `xcodebuild build -sdk iphoneos CODE_SIGNING_ALLOWED=NO` → 打包 `Payload/Koma.app` 成 `Koma.ipa` → 作为 Artifact 上传；打 tag 时同时发布到 Release。
4. 用户在手机上下载 IPA，用 TrollStore 安装。
5. CI 同时在 iOS 模拟器上运行单元测试。

### 5.10 测试

- 单元测试：源协议的解析（使用 MangaDex 和 OPDS 的录制响应作为测试数据）、JS 插件桥接（fetch、parseHTML、超时、异常）、数据库读写、备份/恢复往返。
- 手动验收清单：每种阅读模式下翻页、缩放、切章；书架到详情的转场；下载切到后台；断网时的提示。

## 6. 留给实现者决定

- 具体的配色色值、App 图标、插画素材。
- 各界面的具体间距和动画参数（遵循 5.5、5.6 的原则即可）。
- JS 插件 API 的细节命名（以插件开发文档为准）。
- 预加载页数等默认值的微调。

## 7. 分阶段交付（建议）

1. **M1 骨架**：XcodeGen 工程、CI 出 IPA、5 个 Tab 外壳、数据库、本地漫画源、阅读器（翻页 + 条漫）。→ 用户可以先装上手机试手感。
2. **M2 在线**：MangaDex 源、发现/搜索、详情页、书架、历史、转场动画。
3. **M3 扩展**：JS 插件系统和仓库管理、WebView 过盾、OPDS。
4. **M4 完善**：下载、备份/恢复、设置项、性能调优、空状态和细节打磨。
