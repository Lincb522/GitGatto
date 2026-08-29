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

<br>

![GitGatto 工作区：工作区变更、暂存区与逐行差异](docs/media/workspace.png)

<p align="center"><sub>工作区变更 · 文件暂存 · 逐行 Diff</sub></p>

<br>

GitGatto 把本地仓库、GitHub 项目和命令行 Agent 放进同一套原生界面。仓库状态来自真实 Git 数据；提交、拉取、推送与远端操作始终由明确的操作触发。

## 从改动到协作

<table>
  <tr>
    <td width="33.33%" align="center" valign="top">
      <strong>01 · 打开仓库</strong><br>
      <sub>本地目录、账号项目或搜索结果</sub>
    </td>
    <td width="33.33%" align="center" valign="top">
      <strong>02 · 审阅改动</strong><br>
      <sub>代码 Diff、图片、SVG 与视频</sub>
    </td>
    <td width="33.33%" align="center" valign="top">
      <strong>03 · 组织暂存</strong><br>
      <sub>按文件确定本次提交边界</sub>
    </td>
  </tr>
  <tr>
    <td width="33.33%" align="center" valign="top">
      <strong>04 · Agent 起草</strong><br>
      <sub>从真实暂存 Diff 生成提交信息</sub>
    </td>
    <td width="33.33%" align="center" valign="top">
      <strong>05 · 提交并同步</strong><br>
      <sub>提交、Pull、Push 与上游状态</sub>
    </td>
    <td width="33.33%" align="center" valign="top">
      <strong>06 · GitHub 协作</strong><br>
      <sub>Pull Request、Actions 与 Releases</sub>
    </td>
  </tr>
</table>

工作区会持续更新分支、暂存、工作树和上游状态。切换项目时先恢复可用快照，再在后台校准仓库数据，避免等待完整历史读取后才能继续操作。

## 功能全景

<table>
  <tr>
    <td width="50%" valign="top">
      <strong>工作区与暂存</strong><br><br>
      按文件查看已暂存与未暂存改动，阅读逐行 Diff，预览图片、SVG 与视频；支持暂存、取消暂存、提交、Pull、Push 和分支切换。
    </td>
    <td width="50%" valign="top">
      <strong>提交与历史</strong><br><br>
      浏览提交历史和单文件时间线，查看一次提交中的文本与媒体变化；提交信息可手动填写，也可根据当前 Diff 由 Agent 起草。
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>项目与文档</strong><br><br>
      在应用内浏览完整目录、代码与 README。仓库内链接原位响应，Markdown 图片与引用直接渲染，译文保存在本机并可随时切换。
    </td>
    <td width="50%" valign="top">
      <strong>分支与冲突</strong><br><br>
      查看分支、工作树和上游关系；冲突工作区同时呈现冲突块与合并结果，可编辑结果并在确认后标记为已解决。
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>GitHub 协作</strong><br><br>
      读取账号项目，搜索仓库与开发者，查看 Pull Request、Actions 和 Releases；支持 Star、Fork、克隆及发布资源下载。
    </td>
    <td width="50%" valign="top">
      <strong>应用仓库</strong><br><br>
      检索 GitHub 上带发行包的应用，按平台筛选版本，在详情页阅读说明并管理下载；macOS 应用可从下载结果继续安装。
    </td>
  </tr>
</table>

## Agent 贯穿真实仓库状态

Agent 的工作目录始终指向当前选择的仓库。它能读取工作区、暂存 Diff、分支和上游状态，用于完成这些仓库任务：

- **起草提交**：根据真实改动生成简洁或完整的提交信息；暂存区为空时可先自动暂存当前改动。
- **处理错误**：从错误报告直接诊断 Git LFS、签名、Hook、冲突、上游、权限和推送失败，并保留完整操作记录。
- **维护 README**：依据仓库文件重组文档，在写入前渲染完整预览；“提交应用”会暂存 README、创建提交并推送当前分支。
- **协助审查**：分析变更与 Pull Request 上下文，整理问题、回复和后续修改建议。
- **自然语言搜索**：把项目描述转换为 GitHub 检索条件；直接输入仓库名或开发者名时走常规搜索。

项目操作、文档翻译和搜索使用独立执行通道。一个长时间运行的仓库任务不会占用翻译执行器，任务可以取消，对话与操作记录会在本机保留。

### 可用执行器

| 执行器 | 接入方式 |
| --- | --- |
| Codex CLI | 内置配置 |
| Claude Code | 内置配置 |
| Gemini CLI | 内置配置 |
| OpenCode | 内置配置 |
| 其他 CLI | 自定义可执行文件、参数模板和输入方式 |

GitGatto 复用各 CLI 已有的本机登录状态，不在应用中保存对应账号凭据。

## GitHub 不只是远端列表

- **账号项目**：通过本机 GitHub CLI 的现有登录读取可访问仓库。
- **项目发现**：项目与开发者支持模糊搜索、自然语言检索和继续加载；每日推荐来自 GitHub 实时数据。
- **完整详情**：概览、目录、代码、README、Releases、Pull Request 与 Actions 在应用内保持同一项目上下文。
- **发行资源**：查看版本说明、选择附件、跟踪下载进度，并从下载中心继续处理。
- **远端操作**：Star、Fork、评论、克隆与推送只在对应操作被明确触发后执行。

## 为代码阅读设计的原生界面

GitGatto 提供默认、轻毛玻璃和控制台三套独立主题。每套主题都有自己的窗口材质、工作区布局和控件样式，并共同支持：

- 浅色、深色与跟随系统外观
- 可配置强调色
- 简体中文与英文界面
- 键盘导航与减少动态效果
- 图片、SVG、常见视频格式和 Markdown 内容预览
- 代码、Diff 与冲突结果的行号、语法层级和状态标识

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

<table>
  <tr>
    <td><strong>界面</strong></td>
    <td>SwiftUI、AppKit</td>
    <td><strong>内容渲染</strong></td>
    <td>WebKit、AVKit</td>
  </tr>
  <tr>
    <td><strong>版本控制</strong></td>
    <td>系统 Git、GitHub CLI</td>
    <td><strong>网络与更新</strong></td>
    <td>Alamofire 5.12、Sparkle 2.9</td>
  </tr>
</table>

## 开始使用

1. 从 [GitHub Releases](https://github.com/Lincb522/GitGatto/releases/latest) 下载最新 DMG。
2. 将 GitGatto 拖入“应用程序”文件夹并打开。
3. 选择一个本地 Git 仓库，或从 GitHub 账号项目、搜索结果和每日推荐中打开项目。

### 可选能力

| 功能 | 需要 |
| --- | --- |
| 本地 Git 管理 | 系统中可用的 Git |
| GitHub 账号、搜索与协作 | 已安装并完成登录的 [GitHub CLI](https://cli.github.com/) |
| Agent 操作 | 至少一个已安装并完成登录的受支持 CLI |

本地项目不会被自动批量加入。设备扫描由用户手动启动，可在后台继续；扫描完成后，只有具备访问权限的仓库会进入候选列表，并由用户逐项选择。

## 数据与操作边界

- 设置、Agent 对话、操作记录、下载记录和 README 译文保存在本机。
- Git、SSH、GitHub CLI 与 Agent CLI 使用各自既有的凭据来源；GitGatto 不读取或保存令牌、密码和私钥。
- Agent 默认只读。开启修改权限后，文件操作仍限定在当前仓库。
- 暂存、提交、Pull、Push、Fork、评论、下载和安装都有独立的确认动作。
- 全局错误报告保留应用错误代码、命令退出代码和完整输出，并在展示前移除可能的敏感值。

## 文档

| 文档 | 内容 |
| --- | --- |
| [版本日志](CHANGELOG.md) | 每个正式版本的新增、改进与修复 |
| [贡献指南](CONTRIBUTING.md) | Issue、代码修改与提交要求 |
| [安全策略](SECURITY.md) | 漏洞报告范围与私密报告方式 |
| [产品约束](PRODUCT.md) | 产品边界、交互原则与数据约束 |
| [架构说明](docs/ARCHITECTURE.md) | Git、GitHub、Agent、扫描与更新模块边界 |
| [第三方许可](THIRD_PARTY_NOTICES.md) | 依赖和视觉资源的归属与许可 |

## 参与贡献

功能建议与可复现的问题请提交至 [Issues](https://github.com/Lincb522/GitGatto/issues)。代码贡献请先阅读 [贡献指南](CONTRIBUTING.md)。安全问题请按 [安全策略](SECURITY.md) 使用私密报告渠道，不要在公开 Issue 中附带凭据或私有仓库内容。

## 致谢

感谢以下项目及其维护者：

- [Sparkle](https://github.com/sparkle-project/Sparkle) — 应用内更新
- [Alamofire](https://github.com/Alamofire/Alamofire) — 下载与网络传输
- [GitHub CLI](https://github.com/cli/cli) — GitHub 登录与 API 访问
- [Zappicon](https://zappicon.com/) — 界面图标资源

第三方组件与视觉资源的完整归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可

GitGatto 由 **ZIJIU522** 开发，基于 [MIT License](LICENSE) 开源。
