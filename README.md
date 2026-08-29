<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto 图标">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">
  原生 macOS Git 客户端，以本机 Agent 串联改动审阅、提交、同步与 GitHub 协作。
</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/Lincb522/GitGatto/releases/latest">下载最新版</a></strong>
  &nbsp;·&nbsp;
  <a href="CHANGELOG.md">版本日志</a>
  &nbsp;·&nbsp;
  <a href="CONTRIBUTING.md">参与贡献</a>
</p>

<p align="center">
  <a href="#从改动到协作">工作流</a>
  &nbsp;·&nbsp;
  <a href="#功能全景">功能</a>
  &nbsp;·&nbsp;
  <a href="#agent-贯穿真实仓库状态">Agent</a>
  &nbsp;·&nbsp;
  <a href="#技术栈">技术栈</a>
  &nbsp;·&nbsp;
  <a href="#开始使用">开始使用</a>
</p>

![GitGatto 工作区：工作区变更、暂存区与逐行差异](docs/media/workspace.png)

GitGatto 把本地仓库、GitHub 项目和命令行 Agent 放进同一套原生界面。分支、暂存区、工作树和上游状态来自真实 Git 数据；暂存、提交、同步和远端写入只在对应操作被明确触发后执行。

## 从改动到协作

1. **打开仓库**：选择本地目录、GitHub 账号项目、搜索结果或每日推荐。
2. **审阅改动**：查看已暂存与未暂存文件、逐行 Diff，以及图片、SVG 和视频。
3. **组织提交**：按文件暂存或取消暂存，确定本次提交边界。
4. **起草信息**：手动填写，或让 Agent 根据当前 Diff 生成简洁或完整的提交信息。
5. **提交并同步**：执行 Commit、Pull 或 Push，并查看分支与上游状态。
6. **继续协作**：在同一项目上下文中查看 Pull Request、Actions 和 Releases。

切换项目时，GitGatto 会先恢复可用快照，再在后台校准仓库数据；工作区状态会持续刷新。

## 功能全景

### Git 工作区

- 按文件区分已暂存与未暂存改动，支持暂存、取消暂存、提交、Pull、Push 和分支切换。
- 浏览提交历史、单文件时间线和一次提交中的文本或媒体变化。
- 查看分支、工作树和上游关系；冲突工作区同时呈现冲突块与合并结果，可编辑结果并在确认后标记为已解决。
- 预览图片、SVG、常见视频格式和 Markdown；代码、Diff 与冲突结果包含行号、语法层级和状态标识。

### 项目与 GitHub

- 浏览完整目录、代码和 README；仓库内链接原位响应，Markdown 图片与引用直接渲染，译文保存在本机并可随时切换。
- 通过本机 GitHub CLI 的现有登录读取可访问的账号项目；搜索仓库和开发者，支持模糊匹配、继续加载以及来自 GitHub 实时数据的每日推荐。
- 在项目详情中查看概览、目录、代码、README、Releases、Pull Request 和 Actions；支持 Star、Fork、克隆、评论及发行资源下载。
- 查看版本说明、选择发行附件、跟踪下载进度，并从下载中心继续处理。
- 在应用仓库中检索带发行包的项目，按平台筛选版本，阅读说明并管理下载；macOS 应用可从下载结果继续安装。

所有 Star、Fork、评论、克隆、Push、下载和安装操作都由对应的明确操作触发。

### 原生界面

- 默认、轻毛玻璃和控制台三套独立主题，各自使用对应的窗口材质、工作区布局和控件样式。
- 支持浅色、深色与跟随系统外观，可配置强调色。
- 提供简体中文与英文界面、键盘导航和减少动态效果支持。

## Agent 贯穿真实仓库状态

Agent 的工作目录始终是当前选择的仓库，并可读取工作区、暂存 Diff、分支和上游状态。

- **起草提交**：根据真实改动生成提交信息；暂存区为空时可先自动暂存当前改动。
- **处理错误**：诊断 Git LFS、签名、Hook、冲突、上游、权限和推送失败，并保留完整操作记录。
- **维护 README**：依据仓库文件重组文档，写入前渲染完整预览；“提交应用”会暂存 README、创建提交并推送当前分支。
- **协助审查**：分析变更与 Pull Request 上下文，整理问题、回复和后续修改建议。
- **自然语言搜索**：把项目描述转换为 GitHub 检索条件；直接输入仓库名或开发者名时使用常规搜索。

项目操作、文档翻译和搜索使用独立执行通道，长时间运行的仓库任务不会占用翻译执行器。任务可以取消，对话与操作记录会保存在本机。

### 可用执行器

| 执行器 | 接入方式 |
| --- | --- |
| Codex CLI | 内置配置 |
| Claude Code | 内置配置 |
| Gemini CLI | 内置配置 |
| OpenCode | 内置配置 |
| 其他 CLI | 自定义可执行文件、参数模板和输入方式 |

GitGatto 复用各 CLI 已有的本机登录状态，不在应用中保存对应账号凭据。

## 开始使用

### 安装

1. 从 [GitHub Releases](https://github.com/Lincb522/GitGatto/releases/latest) 下载最新 DMG。
2. 将 GitGatto 拖入“应用程序”文件夹并打开。

### 使用

1. 选择一个本地 Git 仓库，或从 GitHub 账号项目、搜索结果和每日推荐中打开项目。
2. 在工作区审阅 Diff，并按文件组织暂存内容。
3. 手动填写或使用 Agent 起草提交信息，提交变更后再按需 Pull 或 Push。
4. 按需进入历史、分支、冲突、Pull Request、Actions 或 Releases 继续处理。

### 可选能力

| 功能 | 需要 |
| --- | --- |
| 本地 Git 管理 | 系统中可用的 Git |
| GitHub 账号、搜索与协作 | 已安装并完成登录的 [GitHub CLI](https://cli.github.com/) |
| Agent 操作 | 至少一个已安装并完成登录的受支持 CLI |

本地项目不会被自动批量加入。设备扫描由用户手动启动，可在后台继续；扫描完成后，只有具备访问权限的仓库会进入候选列表，并由用户逐项选择。

## 技术栈

<p align="center">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-macOS-1674EA?style=for-the-badge&logo=swift&logoColor=white">
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-native-1F2328?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="WebKit" src="https://img.shields.io/badge/WebKit-content-006CFF?style=for-the-badge&logo=safari&logoColor=white">
</p>

<p align="center">
  <img alt="Git" src="https://img.shields.io/badge/Git-system_CLI-F05032?style=flat-square&logo=git&logoColor=white">
  <img alt="GitHub CLI" src="https://img.shields.io/badge/GitHub_CLI-account_%26_API-181717?style=flat-square&logo=github&logoColor=white">
  <img alt="Alamofire 5.12" src="https://img.shields.io/badge/Alamofire-5.12-D81B60?style=flat-square">
  <img alt="Sparkle 2.9" src="https://img.shields.io/badge/Sparkle-2.9-2DA44E?style=flat-square">
  <img alt="AVKit" src="https://img.shields.io/badge/AVKit-media-8A2BE2?style=flat-square&logo=apple&logoColor=white">
</p>

| 模块 | 技术 |
| --- | --- |
| 界面 | SwiftUI、AppKit |
| 内容渲染 | WebKit、AVKit |
| 版本控制 | 系统 Git、GitHub CLI |
| 网络与更新 | Alamofire 5.12、Sparkle 2.9 |

## 数据与操作边界

- 设置、Agent 对话、操作记录、下载记录和 README 译文保存在本机。
- Git、SSH、GitHub CLI 与 Agent CLI 使用各自既有的凭据来源；GitGatto 不读取或保存令牌、密码和私钥。
- Agent 默认只读；开启修改权限后，文件操作仍限定在当前仓库。
- 暂存、提交、Pull、Push、Fork、评论、下载和安装都有独立的确认动作。
- 全局错误报告保留应用错误代码、命令退出代码和完整输出，并在展示前移除可能的敏感值。

## 支持与文档

功能建议与可复现的问题请提交至 [Issues](https://github.com/Lincb522/GitGatto/issues)。代码贡献请先阅读 [贡献指南](CONTRIBUTING.md)。安全问题请按 [安全策略](SECURITY.md) 使用私密报告渠道，不要在公开 Issue 中附带凭据或私有仓库内容。

| 文档 | 内容 |
| --- | --- |
| [版本日志](CHANGELOG.md) | 每个正式版本的新增、改进与修复 |
| [贡献指南](CONTRIBUTING.md) | Issue、代码修改与提交要求 |
| [安全策略](SECURITY.md) | 漏洞报告范围与私密报告方式 |
| [产品约束](PRODUCT.md) | 产品边界、交互原则与数据约束 |
| [架构说明](docs/ARCHITECTURE.md) | Git、GitHub、Agent、扫描与更新模块边界 |
| [第三方许可](THIRD_PARTY_NOTICES.md) | 依赖和视觉资源的归属与许可 |

## 致谢

- [Sparkle](https://github.com/sparkle-project/Sparkle) — 应用内更新
- [Alamofire](https://github.com/Alamofire/Alamofire) — 下载与网络传输
- [GitHub CLI](https://github.com/cli/cli) — GitHub 登录与 API 访问
- [Zappicon](https://zappicon.com/) — 界面图标资源

第三方组件与视觉资源的完整归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可

GitGatto 由 **ZIJIU522** 开发，基于 [MIT License](LICENSE) 开源。
