<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">原生构建，由 Agent 驱动的 Git 管理工具。</p>

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

GitGatto 是面向 macOS 的原生 Git 与 GitHub 客户端。仓库状态来自系统 Git，远端操作使用 GitHub CLI，Agent 使用本机已经安装并登录的 CLI；应用负责把分散的状态、步骤和结果放回同一个项目界面。

## 为什么做 GitGatto

一次完整的交付经常横跨终端、编辑器、GitHub、Actions 和发布页。中间任何一步失败，都要重新核对分支、暂存内容、运行记录和构建产物。Agent 加入之后，又多了工作目录、执行权限和上下文是否对应当前仓库的问题。

GitGatto 从这些日常问题开始：保留真实的 Git 与现有工具，把仓库操作、GitHub 协作、Agent 处理和失败证据连成一条可以检查、暂停和继续的流程。

## 特色功能

### 项目目标

“交付当前修改”“GitHub 交付”和“完整发布”会按依赖顺序检查暂存、提交、Push、Pull Request、Review、Actions、构建产物、Release、DMG、Appcast 与本机版本。也可以用自然语言描述结果，确认条件后再执行。

每一步都读取 Git、GitHub 或本机的实际状态。任务中断时保留已完成步骤；Actions 失败可以连同运行证据交给 Agent。合并、发布标签和安装仍需单独确认。

### 变更编排与取证

- 变更中心按文件或 Diff 分块整理改动意图，可拆成多个原子提交；执行前核对仓库指纹并创建恢复点，任一提交或验证失败时恢复原有 HEAD 与暂存边界。
- 代码缘由从文件行追溯提交，并在 GitHub CLI 可用时补齐关联 Pull Request、Issue、Review 与 Checks。
- 故障胶囊将补丁、未跟踪文件、基准提交、失败命令、输出和工具版本封装为 `.gatto`；导入后校验内容，并在独立 worktree 中恢复现场。
- 活动记录保存 Git 引用和文件状态变化，并列出当时工作目录位于仓库内的 Agent 进程；关联强度会明确标注，不把相关性写成确定责任。

### 回归取证

在独立 worktree 中运行 `git bisect`，不切换当前工作区。自动模式执行指定验证命令，手动模式逐个标记正常、故障或跳过；候选提交、退出码、耗时和输出会随任务保存。定位首个故障提交后，可以继续让 Agent 修复、复验并创建 Pull Request。

### 仓库灾备

灾备中心监控已加入 GitGatto 的本地仓库，按计划保存未提交代码，并在变更文件数或行数达到阈值时立即创建恢复点；也可以随时手动备份。没有新改动或内容指纹未变化时不会重复写入。

备份包含仓库 Git bundle 与未提交文件副本，每个仓库最多保留三份滚动恢复点。可以查看占用、打开备份目录、删除单份或整仓备份，并将恢复点还原为新的仓库副本。更换备份位置时，GitGatto 会迁移现有内容并核对迁移结果。

### 面向 Git 的 Agent

支持 Codex CLI、Claude Code、Gemini CLI、OpenCode 和自定义 CLI。仓库操作、翻译与软件安装使用独立执行通道，长任务不会占住文档翻译。

Agent 可以根据完整错误输出处理 Git、Git LFS、Hook、签名、分支、同步、冲突、Pull Request 和 Actions 问题；暂存区为空时可先暂存再起草提交信息，随后直接提交或提交并推送。README 重写会先渲染完整结果，再由“提交应用”只提交对应文档。

## Git 与 GitHub

- 管理工作区、暂存区、提交、Pull、Push、分支、贮藏和工作树。
- 查看逐行 Diff、提交图、Blame、单文件历史，以及历史版本中的图片、SVG 和视频。
- 编辑合并、变基与贮藏冲突结果，并继续、跳过或中止当前操作。
- 从当前 GitHub 账号加载可访问仓库，搜索仓库与开发者，并支持模糊检索、自然语言检索和继续加载。
- 在应用内查看代码、README、Pull Request、Actions、Releases 和发行附件。
- 审阅 Pull Request 文件、标记已查看、发布行评论、回复与 Review；重新运行或取消 Actions，并下载构建产物。
- Star、Fork、克隆仓库；本地项目通过手动扫描选择加入，不会整盘自动导入。

## 文档、翻译与内容预览

- 渲染仓库 Markdown、相对路径图片和应用内链接，不把文档阅读交给外部浏览器。
- 自动识别文档语言并调用单独的 Agent 通道翻译；译文按原文版本保存在本机，可直接切换。
- 预览源码、图片、SVG 源码与媒体文件；工作区、提交历史和文件历史使用同一套内容查看器。
- README Agent 根据仓库文件、依赖与现有素材重组文档，而不是只替换措辞。

## 应用仓库与开发工具

- 从 GitHub Releases 检索可安装应用，读取实际图标、介绍、截图、版本和安装包；DMG 与 ZIP 使用本机安装流程，其他格式交给 Agent。
- 开发工具中心收录 99 种运行环境、构建工具、容器、云工具、数据库和命令行工具，并检测本机版本与可用更新。
- 安装与升级支持三路并发队列、多选和批量升级；Homebrew 变更使用单独串行队列，避免依赖同时写入 Cellar。
- Agent 安装后继续完成当前用户所需的 PATH、组件注册、初始化与配置迁移，再重新检查可执行文件和版本。
- 下载、安装、配置与验证过程保留阶段进度、原始输出和已知错误的本地化说明。

## 项目文档

- [路线图](docs/ROADMAP.md)：已实现阶段、下一步计划与边界。
- [架构图](docs/ARCHITECTURE.md)：状态所有权、服务边界与关键数据流。
- [Star History](https://www.star-history.com/#Lincb522/GitGatto&Date)：GitHub Star 增长记录。

![GitGatto roadmap](docs/media/roadmap.svg)

![GitGatto architecture](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

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

- 设置、仓库列表、项目目标、回归取证记录、Agent 对话与操作记录、下载记录和译文保存在本机。
- 开启灾备后，Git bundle 与未提交文件副本保存在应用支持目录或你选择的位置；每个仓库最多保留三份，可在灾备中心单独删除或全部清理。
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
