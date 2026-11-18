# Koma 项目交接文档（上下文快照）

- 快照时间：2026-11-18
- 用途：新的会话读完这份文档，就能从断点继续开发，不需要重新了解背景。

## 1. 项目是什么

**Koma**：一款**自用**的 iOS 漫画阅读 App，通过 **TrollStore** 安装在用户的 iPhone 上（**iOS 16.3.1**），**不开启开发者模式**。

用户的核心诉求：
1. 界面**高级、好看**，一眼就会用（已批准深色优先的视觉方向）
2. 功能齐全：书架、发现、搜索、阅读器、历史、下载、设置
3. **装好就能用的漫画源，包含 18+ 内容**
4. **所有操作都要丝滑**（支持 120Hz，加载图片时不闪、不跳）
5. **中国大陆用户也能流畅使用**

## 2. 关键约束

- 开发机是 **Windows，没有 Mac / Xcode**。所有编译和测试都在 **GitHub Actions**（`macos-15`）上进行。
- 仓库：https://github.com/yizhimao213/koma （公开仓库），开发分支 `feat/m1`，`main` 上只有最初的文档。
- 推送使用 GitHub CLI（`C:\Program Files\GitHub CLI\gh.exe`，已登录）。网络偶尔会出现 TLS 握手失败，重试即可。
- 产物是未签名 IPA（`CODE_SIGNING_ALLOWED=NO`），交给 TrollStore 安装。打 `v*` 标签时会自动发布到 Release。
- 部署目标 **iOS 16.0**：不能用 SwiftData、`@Observable` 等 iOS 17 才有的 API；使用 Swift 5 语言模式；**App 编译必须 0 警告**。
- 版权立场：**不内置盗版站爬虫**。内置源只有 MangaDex（官方 API，含 18+ 分级）、本地文件、OPDS；其他站点由用户通过插件仓库自行添加（M3）。用户要求过内置盗版源，已明确拒绝。
- 对话风格：用户希望 Claude 用"二次元元气少女老师"的语气聊天，自称"人家"；代码、注释、提交信息、文档保持专业写法。

## 3. 技术栈与结构

- `Packages/KomaCore`：纯逻辑 Swift 包，包括模型、源协议、GRDB 数据库、本地导入、阅读器会话、网络层、MangaDex 源、书架更新器、浏览缓存、连通性探测。XCTest 单测在 CI 上运行。
- `App/`：SwiftUI 外壳 + UIKit 阅读器（`App/Reader/*`），使用 Nuke 12 / NukeUI 加载图片。
- 工程由 XcodeGen（`project.yml`）生成；CI 配置见 `.github/workflows/build.yml`。
- 设计文档：`docs/superpowers/specs/2026-11-18-comic-reader-design.md`（§5.6.1 高级视觉，§5.6.2 中国网络，§5.2 18+）
- 计划：`docs/superpowers/plans/2026-11-18-koma-m1-skeleton-local-reader.md`、`docs/superpowers/plans/2026-11-18-koma-m2-mangadex-premium-ui.md`
- 执行记录（git 已忽略，只在本地）：`.superpowers/sdd/<plan>/progress.md`，其中有每个任务的状态、裁决和延后的小问题。

## 4. 当前进度

### M1 ✅ 已完成，发布 v0.1.0（标签指向 `cba2f30`）
本地漫画导入（CBZ/ZIP/PDF/文件夹，支持 GBK 文件名）、书架、详情页、UIKit 阅读器（LTR/RTL/竖向/条漫、缩放、自动续章、进度保存）、历史、设置。CI 全部通过，总审查发现的问题已修复。

### M2 ⏸ 进行到一半时由用户叫停（HEAD = `32fda5f`，已推送）

| 任务 | 状态 |
|---|---|
| 1 网络层（重试/超时/限速） | ✅ 已审查，CI 通过 |
| 2 MangaDex 源 | ✅ 已审查，CI 通过 |
| 3 书架更新器 / 章节清理 / 浏览缓存 / 连通性探测 | ✅ 已审查，CI 通过（7f8e950）；修复提交 7e2e66d 未单独跑 CI |
| 4 内容（18+）和网络设置，注册 MangaDex | ✅ 已审查；最后的修复 `c8953ad` **未通过 CI 验证** |
| 5 设计系统 + 悬浮 Tab 栏 + 书架重做 | ✅ 已审查（9db6676），**未通过 CI 验证** |
| 6 发现页 / 源列表 / 全局搜索 | 代码已提交（32fda5f），**审查做到一半停止，未通过 CI 验证** |
| 7 详情页重做（缓存优先） | ❌ 未开始 |
| 8 阅读器图片超时、备用节点、重试 | ❌ 未开始 |

未通过 CI 验证的原因：GitHub 的 macOS 编译机容量不足，任务排队超时（"The job was not acquired by Runner"），不是代码报错。

### M3 / M4 未开始
- M3：JS 插件源（JavaScriptCore）、插件仓库 `index.json`（带 `nsfw` 字段）、WebView 过盾验证、OPDS
- M4：后台下载、备份/恢复、阅读器适应方式与裁白边，以及各审查中延后的小问题

## 5. 继续开发的步骤

1. 重新触发 CI（推送或 `gh workflow run build.yml --ref feat/m1`），等 `32fda5f` 跑绿。如果编译机长期排不上，可以考虑把 `runs-on` 换成 `macos-14`。
2. 审查 M2 Task 6（简报：`.superpowers/sdd/2026-11-18-koma-m2-mangadex-premium-ui/task-6-brief.md`，报告：`task-6-report.md`）。
3. 执行 Task 7、Task 8，然后对整个 M2 做总审查，修复后打 `v0.2.0` 标签。
4. 用户关心额度（Pro 套餐；本周额度在快照时已用 46%）。已建议从 M3 开始改用省额度模式：只在每个阶段结束时统一审查一次；实现任务主要用 sonnet，只有关键 UI 和阅读器用 opus。

## 6. 主要决策（裁决）

- 没有本地编译环境，以 CI 结果作为测试证据；在 `feat/m1` 上开发，不使用 worktree；M2 继续沿用这个分支。
- CI 使用 macos-15 和默认 Xcode。
- KomaCore 的 `LibraryItem` 改名为 `LibraryEntry`，避免和 SwiftUI 的同名类型冲突。
- 章节主键改为 `(sourceId, mangaId, id)`；本地封面存成相对路径 `local-library:/…`，读取时再解析。
- 仓储类标记为 `@unchecked Sendable`（内部只持有线程安全的 GRDB writer）。
- MangaDex：搜索按相关度排序；推荐轮播永远只显示 safe/suggestive 内容，18+ 内容单独放一行。
- 章节清理：接口返回空列表时不清理；历史记录指向的章节永远保留。
- 设置：镜像地址在失去焦点或离开页面时保存；允许 http 镜像（开启 `NSAllowsArbitraryLoads`）。
- 浏览缓存的 key 包含 18+ 开关状态。
- 用户离开时说过"交给你了"，所以 M2 计划没有等用户审阅就开始执行。

## 7. 设备上待验证的项（用户尚未实测）

- 翻页和缩放是否流畅；RTL 模式下点左边是否为下一页；杀掉进程后能否续读
- 导入两本本地漫画后，已读状态是否互不影响；重装 IPA 后封面是否还在
- TrollStore 能否直接安装未签名 IPA（可能需要先在 TrollStore 设置里安装 ldid）
