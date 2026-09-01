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

![GitGatto 工作区](docs/media/workspace.png)

GitGatto 是面向 macOS 的 Git 与 GitHub 客户端。本地仓库状态直接来自 Git；GitHub 功能使用本机 GitHub CLI 的现有登录；Agent 始终在当前选择的仓库中运行。

## Git 工作流

- 管理工作区、暂存区、提交、Pull、Push、分支、贮藏和工作树。
- 查看逐行 Diff、提交图、单文件历史、Blame，以及历史版本中的图片、SVG 和视频。
- 处理合并、变基与贮藏冲突，可编辑结果并继续、跳过或中止操作。
- 检查 Git LFS、Hook、上游和仓库环境问题，并从错误报告直接交给 Agent 处理。
- 将当前修改设为交付目标，持续核对暂存、提交、推送、Pull Request、审查意见、Actions、构建产物与合并状态；Actions 失败可在保留运行证据后交给 Agent 修复，中断后从已确认的步骤继续。
- 手动扫描指定目录，从当前用户可读写的 Git 仓库中选择要加入的项目。

## GitHub

- 加载当前账号可访问的仓库，搜索仓库与开发者，支持模糊检索、自然语言检索和继续加载。
- 在应用内查看 README、目录、代码、Pull Request、Actions、Releases 和发行附件。
- 审阅 Pull Request 文件、标记已查看、发布行评论、回复与 Review；重新运行或取消 Actions，并下载构建产物。
- Star、Fork、克隆仓库，下载和管理发行附件。

## Agent

- 支持 Codex CLI、Claude Code、Gemini CLI、OpenCode 和自定义 CLI；项目操作、翻译与安装使用独立执行通道。
- 暂存区为空时可先暂存当前改动，再起草提交信息；结果可直接提交或提交并推送。
- 根据仓库文件重写 README，先渲染结果，再通过“提交应用”暂存、提交并推送 README。
- 翻译 README、应用介绍和发行说明，译文按内容版本保存在本机。
- 安装命令行发行包与开发工具；安装后完成工具初始化、组件注册、配置迁移和环境设置，并重新验证配置与版本。
- 对话与操作记录按仓库保存；修改和远端写入只在对应操作中执行。

## 应用仓库与开发工具

- 从 GitHub Releases 检索可安装应用，展示实际图标、介绍、截图、版本和安装包；DMG 与 ZIP 使用本机安装流程，其他格式由 Agent 处理。
- 开发工具中心收录 63 种运行环境、构建工具、容器、云工具、数据库和命令行工具，可检测本机状态与 Homebrew 更新，并安装或升级指定软件包。
- 下载、安装、工具配置和版本验证均保留进度与结果。

## 安装

从 [Releases](https://github.com/Lincb522/GitGatto/releases/latest) 下载 DMG，将 GitGatto 拖入“应用程序”。发行包支持 Apple Silicon 与 Intel，最低系统版本为 macOS 14。

| 功能 | 需要 |
| --- | --- |
| 本地仓库 | Git |
| GitHub 仓库、PR、Actions 与远端操作 | 已登录的 [GitHub CLI](https://cli.github.com/) |
| Agent | 至少一个已安装并登录的受支持 CLI |
| Homebrew 更新检测 | Homebrew |

应用内更新、更新日志和安装包均来自本仓库的 GitHub Releases。

## 本地数据与权限

- 设置、仓库列表、项目目标、Agent 对话与操作记录、下载记录和译文保存在本机。
- Git、SSH、GitHub CLI 与 Agent CLI 继续使用各自的凭据来源；GitGatto 不保存令牌、密码或私钥。
- Pull、Push、Fork、评论、Review、Actions 操作、应用安装和开发工具变更均由明确的应用操作触发。

## 开发

需要 macOS 14 及以上版本和项目声明的 Swift 工具链。

```bash
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
open GitGatto.xcodeproj
```

源码使用 Swift 6、SwiftUI、AppKit、WebKit 与 AVKit；网络和更新分别使用 Alamofire 5.12 与 Sparkle 2.9.6。贡献要求见 [CONTRIBUTING.md](CONTRIBUTING.md)，架构边界见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 致谢

- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Alamofire](https://github.com/Alamofire/Alamofire)
- [SwiftUI-Animations](https://github.com/Shubham0812/SwiftUI-Animations)
- [GitHub CLI](https://github.com/cli/cli)
- [Simple Icons](https://github.com/simple-icons/simple-icons)、[VSCode Icons](https://github.com/vscode-icons/vscode-icons)、[Devicon](https://github.com/devicons/devicon) 与 [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)

具体版本与许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。安全问题请通过 [SECURITY.md](SECURITY.md) 中的渠道报告。

## 许可

GitGatto 由 **ZIJIU522** 开发，基于 [MIT License](LICENSE) 开源。
