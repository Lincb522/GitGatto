<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">macOS · Git · GitHub</p>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.pt-BR.md">Português</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.ar.md">العربية</a>
</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon and Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://gatto.zijiu522.cn">官网</a>
  ·
  <a href="https://github.com/Lincb522/GitGatto/releases/latest">下载</a>
  ·
  <a href="CHANGELOG.md">版本日志</a>
  ·
  <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a>
</p>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/media/github-project.png" alt="GitHub 项目"><br><sub><b>GitHub 项目</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/workspace.png" alt="工作区与 Diff"><br><sub><b>工作区与 Diff</b></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="docs/media/recovery-center.png" alt="灾备中心"><br><sub><b>灾备中心</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/file-time-machine.png" alt="文件时间机器"><br><sub><b>文件时间机器</b></sub></td>
  </tr>
</table>

GitGatto 是 macOS 原生 Git 与 GitHub 客户端，支持 Apple Silicon 和 Intel。除了日常仓库操作，还提供未提交代码备份、外部 Agent 活动记录、目标交付、回归定位和开发环境安装。

<a id="why"></a>
## 为什么做 GitGatto

写 GitGatto，是因为写完代码以后的事情同样费时间：整理一堆混在一起的改动，查一个回归从哪次提交开始，等 CI、审 PR、发版本。临时切换任务还容易弄丢草稿和未提交文件。

用了 Agent 以后，又多了几个实际问题：它改了什么、为什么这样改、失败时留下了什么，以及它说“完成”之后结果到底能不能用。我们想把这些事做好，而不是只给 Git 命令套一层按钮。GitGatto 继续使用系统 Git 和本机 CLI，让改动、证据、恢复点和后续操作都能查到。

[灾备与保护](#recovery) · [状态栏监控](#monitoring) · [目标交付](#goals) · [变更编排](#intent) · [回归取证](#regression) · [项目工具](#project-tools) · [安装与配置](#install-tools)

<a id="features"></a>
## 特色功能

<a id="recovery"></a>
### 未提交代码的灾备，与外部 Agent 保护

灾备中心保护加入 GitGatto 的本地仓库。定时保存、重大改动触发和手动备份都支持；内容没变时不重复创建。恢复点包含 Git bundle 和未提交文件副本，每个仓库最多轮换保留三份，不会随着运行时间无限堆积。

- 应用内 Agent 写入前可创建恢复点；仓库守卫也观察外部 Agent、终端和脚本带来的文件删除、未提交内容丢失、引用回退及仓库不可用。
- 异常记录列出原因和受影响路径，可以直接检查仓库或打开恢复点。提醒表示需要核对，不代表已经认定某个进程误操作。
- 恢复点分阶段写入并带完整性标记，异常退出后不把未完成副本当成有效备份。
- 可以查看空间占用、删除单份或整仓备份；更换目录会迁移现有内容。“恢复副本”写入新目录，不覆盖源仓库。

这不是系统级命令拦截器，也不能保证找回尚未保存或被备份规则排除的文件。

<a id="monitoring"></a>
### 不打开主窗口，也能看仓库情况

状态栏可以独立选择所有仓库或单个仓库，不跟着主窗口的选择走。查看未提交改动、上游同步、恢复点、Actions、目标状态，以及最近一年的每日活动点阵图。

工作区、远程同步、仓库保护、Actions 和目标分别有监控开关；总开关、状态栏开关和刷新间隔都在设置里。点阵统计提交和监测到的本地改动，不是工时。应用保持运行时可在后台监控，退出应用后停止。

<a id="goals"></a>
### 把交付过程保存成可继续的目标

目标提供“交付当前修改”“GitHub 交付”“完整发布”和自然语言自定义。创建前先看步骤，执行后查看当前进度、阻塞原因和记录；可搜索目标、筛选进行中与历史任务。

根据所选流程，逐项核对暂存、提交、Push、PR、Review、Actions、构建产物、Release、DMG、Appcast 和本机版本。自定义目标由 Agent 生成候选条件，确认后才执行。中断后重新读取实际状态再继续，不把 Agent 的文字回复当成成功结果；合并、发布标签和安装仍有单独确认。

<a id="intent"></a>
### 把混在一起的改动拆成提交

变更中心按文件或 Diff 分块分组，可以分别写提交说明，也可以让 Agent 整理分组。执行前检查是否遗漏、重复分配，以及仓库是否已经变化，再创建恢复点并按顺序提交。

每个提交会运行差异检查或指定的验证命令。中途失败会尝试回退原 HEAD 和暂存边界；恢复点仍可用于检查，不承诺任何错误下都能自动回退成功。

<a id="regression"></a>
### 在独立工作树里定位回归

回归取证用 `git bisect` 缩小首个故障提交的范围，不切换正在工作的目录。自动模式运行验证命令；手动模式把候选标为正常、故障或跳过。提交、判定、退出码、耗时和输出随任务保存。

定位后可把证据交给 Agent 修复、复验并准备 PR。验证命令必须能判断你要找的问题，跳过太多提交时不一定能得到唯一结论。

<a id="evidence"></a>
### 代码缘由、故障胶囊与活动记录

- **代码缘由**：从文件行追溯提交，在 GitHub CLI 可用时继续查看关联 PR、Issue、Review 和 Checks。
- **故障胶囊**：把基准提交、补丁、允许收录的未跟踪文件、失败命令、输出和工具版本导出为 `.gatto`。导入时校验结构与摘要，再在独立工作树恢复；不会自动执行包里的命令。只过滤已知敏感路径和可识别内容，分享前仍需检查。
- **外部 Agent 活动记录**：将文件和 Git 引用变化，与当时工作目录位于仓库中的已知 Agent 进程关联，显示证据强度。进程恰好在运行，不等于能证明每次改动都是它造成的。

<a id="agent"></a>
### Agent 不只起草提交说明

支持 Codex CLI、Claude Code、Gemini CLI、OpenCode 和自定义 CLI。内置 Git 处理指引覆盖暂存审阅、提交起草、冲突、分支整理、历史恢复、仓库健康和发布检查，也可携带 Git LFS、hooks、签名或同步失败的原始输出继续排查。

项目处理、翻译、搜索和安装有独立执行通道。README 重写先预览再应用；Issue 和 PR 回复根据讨论与差异起草，可编辑，确认后才发送。工具和模型使用你配置的 CLI，不要求更换现有 Agent。

<a id="project-tools"></a>
### 切换任务时，保存的不只是分支

**工作现场**可保存暂存与未暂存改动、未跟踪文件、分支、草稿、所选文件及关联目标和链接。恢复时核对仓库状态；也可以在独立工作树中打开。被忽略文件不在保存范围，现场不是独立备份。

| 工具 | 能做什么 |
| --- | --- |
| 代码搜索 | 跨已管理仓库搜索当前文件、指定版本或历史改动；按目录、语言、扩展名筛选，预览后把证据交给 Agent。普通文本匹配，结果有数量限制。 |
| 运行命令 | 读取项目脚本或添加自定义命令，固定常用项，查看实时输出、耗时和退出状态，支持停止、重试与打开本地服务。非交互执行，自定义参数逐项填写。 |
| 忽略规则 | 查明规则来源，预览后编辑共享 `.gitignore` 或本地 `.git/info/exclude`；停止跟踪时保留磁盘文件。 |
| 提交身份 | 按仓库或目录绑定作者与签名配置，查看生效来源，提交前检查身份一致性。Git 作者身份与 GitHub 登录分开管理。 |

从顶部“项目工具”或 `⌘K` 进入。

<a id="install-tools"></a>
### 安装之后，把配置和验证一起做完

应用仓库从 GitHub Releases 查找版本和安装包，区分下载与安装。DMG、ZIP 使用本机安装流程，需要命令行的交给 Agent；下载管理显示阶段、输出和重试入口。

开发工具库包含 **99 种工具与运行库**，可检测本机版本、多选或批量升级。安装与升级有各自队列，最多三路任务并行；Homebrew 写入串行调度，避免同时修改依赖。

安装任务继续处理需要的 PATH、插件注册、初始化和配置迁移，再检查可执行文件与实际版本。下载成功、Agent 说完成，都不能代替本机验证。缺少权限或配置时保留待处理事项；账号登录、系统授权仍需本人完成。“已安装”应用列表记录 GitGatto 的安装结果，不是整机应用清单。

<a id="git-github"></a>
## Git 与 GitHub 的日常操作

- **工作区与历史**：暂存、提交、Diff、提交图、Blame、文件历史和历史媒体预览；组合搜索 SHA、作者、路径、文本、日期和引用。
- **分支与恢复**：分支、标签、远程、贮藏、工作树、引用比较、Reflog 恢复分支；整理提交支持重排、合并、拆分、修订、拣选、撤销和重置。历史重写会检查已发布提交，破坏性操作需要确认。
- **冲突与诊断**：编辑合并、变基或贮藏冲突，继续、跳过或中止 Git 操作；检查 Git LFS、hooks 和工具环境。
- **多仓库同步**：批量获取、拉取和推送，分别显示领先、落后、分叉、冲突和失败，可重试失败项。
- **GitHub 项目**：账号仓库、仓库与开发者搜索、自然语言检索、Star、Fork、克隆；应用内浏览代码、README、Release 和附件。
- **收件箱、Issue 与 PR**：筛选待审阅、提及、检查失败等事项；创建和处理 Issue；PR 文件审阅、已查看标记、行评论、回复与 Review。
- **Actions**：查看运行和日志、重新运行或取消、下载构建产物。远端写入由明确操作触发，不因刷新页面自动执行。

<a id="reading"></a>
## 阅读与翻译

Markdown、相对路径图片、源码、SVG 和媒体文件可直接预览。文档自动识别语言，使用独立翻译配置；译文按原文、路径和目标语言缓存，原文变化后不复用旧译文。已是目标语言或文本不足时可保持原文。翻译不是自动提交 README。

<a id="appearance"></a>
## 主题与界面

轻雾、轻毛玻璃、控制台、翠影、银页、曜幕共六种主题，区别包括布局、面板、侧栏和控件，不只是强调色。曜幕支持分开调整深浅色的背景、面板、文字、按钮与状态颜色，并提供珊瑚、海盐、松雾、暮紫预设。

侧栏分区可折叠、滚动，工作区域可调节尺寸。界面有 11 种语言，切换无需重启；使用方法见应用内“帮助 → 使用指南”。

<a id="start"></a>
## 安装与开始使用

从 [Releases](https://github.com/Lincb522/GitGatto/releases/latest) 下载 DMG，拖入“应用程序”。最低 macOS 14，发行包支持 Apple Silicon 与 Intel。正式版本和变更以 [更新日志](CHANGELOG.md) 及 Release 为准，README 介绍当前仓库能力。

| 使用范围 | 前置条件 |
| --- | --- |
| 本地 Git 与普通远程同步 | Git，以及相应远程的 Git / SSH 认证 |
| GitHub 账号、PR、Issue、Actions | 已登录的 [GitHub CLI](https://cli.github.com/) |
| Agent、翻译与 Agent 安装 | 对应 CLI 已安装，并按提供方要求完成登录或配置 |
| Homebrew 工具检测与升级 | Homebrew |

打开本地仓库，或手动扫描后选择添加；不会整盘自动导入。GitHub 登录与 Agent 配置在设置中完成。应用更新从 GitHub Releases 和 Appcast 获取。

<a id="data"></a>
## 数据与权限

仓库列表、设置、目标、回归记录、对话、译文、下载记录和恢复点保存在本机；备份位置可更换。Git、SSH、GitHub CLI 和 Agent CLI 复用各自的凭据来源。

“本地保存”不等于“全部离线”：GitHub 功能会访问 GitHub，Agent 与翻译会将所需上下文交给配置的 CLI，后续数据处理取决于该工具及模型服务。执行前检查待发送内容；不要在命令、草稿或故障胶囊里放入凭据。系统目录变更仍受 macOS 授权约束。

<a id="docs"></a>
## 路线图、架构与项目记录

[路线图与后续计划](docs/ROADMAP.md) · [系统架构](docs/ARCHITECTURE.md) · [版本记录](CHANGELOG.md)

![GitGatto 路线图](docs/media/roadmap.svg)

![GitGatto 系统架构](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

路线图依据仓库版本记录，虚线部分为计划；Star History 是已提交的数据快照，在线记录见图中链接。

<a id="development"></a>
## 从源码运行

需要 macOS 14+、Swift 6.1+；Xcode 工程配置见 `project.yml`。

```sh
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
swift run GitGatto
```

也可以打开 `GitGatto.xcodeproj` 使用 `GitGatto` scheme。修改工程结构后，用 XcodeGen 执行 `./scripts/generate-xcodeproj.sh` 重新生成，不手改工程文件。应用使用 SwiftUI、AppKit、WebKit、AVKit、Alamofire 和 Sparkle；版本由 `Package.resolved` 锁定。

<a id="credits"></a>
## 贡献与许可

贡献约定见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全问题见 [SECURITY.md](SECURITY.md)。感谢 [GitHub CLI](https://github.com/cli/cli)、[Sparkle](https://github.com/sparkle-project/Sparkle)、[Alamofire](https://github.com/Alamofire)、[Reicon](https://github.com/Lincb522/reicon) 及图标、动画资源作者；完整来源与许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

GitGatto 由 **ZIJIU522** 开发，基于 [MIT License](LICENSE) 开源。
