<p align="center">
  <img src="Assets/GitGatto-AppIcon.svg" width="112" height="112" alt="GitGatto">
</p>

<h1 align="center">GitGatto</h1>

<p align="center">原生 macOS Git 客户端，把仓库管理、GitHub 协作与本机 Agent 放进同一个工作区。</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest">下载 GitGatto</a>
  ·
  <a href="docs/DOCUMENTATION.md">使用文档</a>
  ·
  <a href="CHANGELOG.md">版本日志</a>
</p>

![GitGatto 工作区](docs/media/workspace.png)

## 功能

### 本地仓库

- 实时读取工作区、暂存区、分支、提交历史与上游状态
- 查看逐行 Diff、图片和视频改动，按文件暂存或撤销暂存
- 切换分支，执行 Pull、Push、提交、冲突处理与历史追踪
- 手动扫描指定目录，在结果中选择需要加入工作区的仓库

### GitHub

- 使用本机 GitHub CLI 的现有登录读取账号仓库
- 搜索仓库与开发者，查看代码、README、Pull Request、Actions 和 Releases
- Star、Fork、克隆仓库，在应用内下载和安装 macOS 发布包
- 在项目与应用仓库中继续加载搜索结果，并保留下载任务进度

### Agent

- 支持 Codex CLI、Claude Code、Gemini CLI、OpenCode 与自定义 CLI
- 项目操作、搜索和翻译使用独立执行通道，互不占用
- 根据真实暂存 Diff 起草提交信息；暂存区为空时可自动暂存当前改动
- 诊断 Git、Git LFS、签名、Hook、冲突、上游与权限错误
- 依据仓库内容重写 README，并在提交前直接查看完整渲染结果

### 阅读与外观

- 在应用内渲染 Markdown、代码、图片、SVG 与视频
- README 译文保存在本机，可随时切换原文与已保存译文
- 提供默认、轻毛玻璃和控制台主题，支持浅色、深色与强调色设置
- 简体中文与英文界面

## 使用

1. 从 [Releases](https://github.com/Lincb522/GitGatto/releases/latest) 下载最新 DMG。
2. 将 GitGatto 拖入“应用程序”文件夹并启动。
3. 打开一个本地仓库，或登录 GitHub 后从账号项目、搜索结果和推荐中选择项目。

GitHub 功能依赖 [GitHub CLI](https://cli.github.com/) 的现有登录。Agent 功能需要至少一个已安装并完成登录的受支持 CLI；执行器和权限可在 GitGatto 设置中分别配置。

## 数据与权限

GitGatto 的设置、Agent 对话、操作记录、下载记录和 README 译文保存在本机。Git、SSH、GitHub CLI 与 Agent CLI 继续使用各自的凭据来源，GitGatto 不读取或保存令牌、密码和私钥。

暂存、提交、Pull、Push、Fork、评论和安装等操作只在对应按钮被明确触发后执行。Agent 默认只读；允许修改时，范围仍限定在当前仓库。

## 参与贡献

问题与功能建议可提交到 [Issues](https://github.com/Lincb522/GitGatto/issues)。代码贡献请先阅读 [贡献指南](CONTRIBUTING.md)；安全问题请使用 [安全策略](SECURITY.md) 中的私密报告渠道。

## 致谢

GitGatto 的实现离不开这些开源项目：

- [Sparkle](https://github.com/sparkle-project/Sparkle) — 应用更新
- [Alamofire](https://github.com/Alamofire/Alamofire) — 下载与网络传输
- [GitHub CLI](https://github.com/cli/cli) — GitHub 登录与 API 访问

界面图标使用 [Zappicon](https://zappicon.com/) 资源。完整第三方归属与许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。感谢所有参与这些项目的维护者与贡献者。

## 许可

GitGatto 由 **ZIJIU522** 开发，基于 [MIT License](LICENSE) 开源。
