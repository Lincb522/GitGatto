<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">原生构建，由 Agent 驱动的 Git 管理工具。</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon and Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
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

![GitGatto 工作区](docs/media/workspace.png)

GitGatto 将本地仓库、GitHub、本机 Agent、应用安装与开发工具放在同一个原生工作区。分支、暂存区、工作树和上游状态均来自当前仓库，Agent 任务始终在当前选择的项目中执行。

## 仓库与协作

### 本地仓库

- 查看已暂存、未暂存、未跟踪和冲突文件，按文件暂存或取消暂存。
- 逐行 Diff、提交、Pull、Push、分支切换、贮藏和工作树管理。
- 提交历史、单文件历史、Blame，以及提交中的文本与媒体变化。
- 合并与变基冲突可对照双方内容、编辑结果并继续或中止操作。
- 手动扫描指定目录，再从有权访问的仓库中选择要加入的项目。

### GitHub

- 使用本机 GitHub CLI 的现有登录读取可访问的账号仓库。
- 搜索仓库与开发者，支持模糊匹配、继续加载和每日推荐。
- 在应用内查看 README、代码、Pull Request、Actions 和 Releases。
- Star、Fork、克隆、发行附件下载与下载管理。

### 项目内容

- 浏览完整目录、代码和 README，仓库内链接直接在应用中响应。
- Markdown 图片、引用和代码块按仓库路径渲染，译文保存在本机并可切换。
- 工作区、提交历史、文件历史和暂存区均可预览图片、SVG 与视频。
- SVG 可在渲染结果与源码之间切换。

### 应用与开发环境

- 应用仓库从 GitHub Releases 检索可安装项目，展示应用图标、详细介绍、实际截图、开发者、版本和发行附件。
- 应用介绍与发布内容可交给 Agent 翻译，译文保存在本机；搜索结果和发行版可继续加载。
- DMG 与 ZIP 使用本机安装流程，其他发行包由 Agent 处理；下载、安装和验证状态在应用内持续更新。
- 开发工具中心收录 63 种常用工具、运行环境、构建工具、容器、云工具和数据库，可扫描本机安装状态并检查 Homebrew 升级。
- 安装或升级只处理当前选择的软件包，完成后重新检测可执行文件与版本。

### 界面

- 轻毛玻璃、轻雾、控制台、翠影和银页五套主题，使用独立布局与样式。
- 浅色、深色、跟随系统与自定义强调色。
- 侧边栏分区可折叠，侧边栏、项目列表和详情区域可单独调宽并记住尺寸。
- 简体中文、英文和减少动态效果支持。

## Agent

每次 Agent 任务都以当前选择的仓库作为工作目录，可读取该仓库的工作区、暂存 Diff、分支和上游状态。

- **提交起草**：暂存区为空时可自动暂存当前改动，再生成简洁或完整的提交信息；结果可直接提交或提交并推送。
- **错误处理**：从全局错误报告进入，诊断 Git LFS、签名、Hook、冲突、上游、权限和推送失败。
- **README 重写**：依据仓库文件重组文档，完成后展示渲染预览；“提交应用”会暂存 README、创建提交并推送当前分支。
- **仓库审查**：检查工作区、暂存内容、历史、Pull Request 和 GitHub Actions 状态。
- **翻译**：翻译 README、应用介绍与发行内容；翻译和项目操作使用独立执行通道。
- **安装与升级**：处理需要命令行安装的发行包，并按选中的软件包安装或升级开发工具，完成后验证结果。
- **执行器**：Codex CLI、Claude Code、Gemini CLI、OpenCode 与自定义 CLI。

项目操作、文档翻译和安装使用独立执行通道。Agent 对话、操作记录与译文按仓库保存在本机。

## 安装

1. 从 [Releases](https://github.com/Lincb522/GitGatto/releases/latest) 下载 DMG。
2. 将 GitGatto 拖入“应用程序”文件夹。

后续版本可在应用内直接检查；更新日志与安装包来自同一个 GitHub Release。

| 功能 | 前置条件 |
| --- | --- |
| 本地仓库 | 系统 Git |
| GitHub 账号与远端功能 | 已安装并登录的 [GitHub CLI](https://cli.github.com/) |
| Agent | 至少一个已安装并登录的受支持 CLI |
| 开发工具安装与升级 | 对应软件包管理器；Homebrew 升级检测需要已安装 Homebrew |

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

## 数据与权限

- 设置、Agent 对话与操作记录、下载记录、README 与应用介绍译文保存在本机。
- Git、SSH、GitHub CLI 和 Agent CLI 使用各自已有的凭据来源；GitGatto 不保存令牌、密码或私钥。
- Agent 默认只读；允许修改后仍限定当前仓库。Pull、Push、Fork、评论、应用安装和开发工具变更由对应操作触发。

## 文档

| 文档 | 内容 |
| --- | --- |
| [版本日志](CHANGELOG.md) | 正式版本变更 |
| [贡献指南](CONTRIBUTING.md) | Issue、代码与提交要求 |
| [安全策略](SECURITY.md) | 漏洞报告范围与渠道 |
| [产品约束](PRODUCT.md) | 产品、交互与数据边界 |
| [架构说明](docs/ARCHITECTURE.md) | Git、GitHub、Agent、扫描与更新模块 |
| [第三方许可](THIRD_PARTY_NOTICES.md) | 依赖与视觉资源归属 |

## 致谢

- [Sparkle](https://github.com/sparkle-project/Sparkle) — 应用内更新
- [Alamofire](https://github.com/Alamofire/Alamofire) — 下载与网络传输
- [GitHub CLI](https://github.com/cli/cli) — GitHub 登录与 API 访问
- [Simple Icons](https://github.com/simple-icons/simple-icons)、[VSCode Icons](https://github.com/vscode-icons/vscode-icons)、[Devicon](https://github.com/devicons/devicon) 与 [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme) — 语言图标来源

其他归属与许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可

GitGatto 由 **ZIJIU522** 开发，基于 [MIT License](LICENSE) 开源。
