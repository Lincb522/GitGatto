# GitGatto

GitGatto 是一款原生开发、由 Agent 驱动的 macOS Git 管理工具。它把本地仓库、GitHub 项目、改动审阅、提交同步、项目文档与本机 AI CLI 放在同一套可追踪的工作流中。

![GitGatto 工作区](docs/media/workspace.png)

## 已实现能力

- **本地 Git**：真实读取工作区和暂存区，查看 Diff、历史和分支，执行暂存、提交、Pull、Push 与分支切换。
- **项目管理**：手动扫描指定目录或设备，后台返回当前用户可读写的仓库，再由用户选择添加；项目按活跃度和修改时间分区。
- **GitHub**：复用本机 GitHub CLI 登录，读取账号项目，搜索仓库与开发者，查看 README、目录、代码和 Pull Request，并支持 Fork 或克隆。
- **项目文档**：在应用内渲染 GitHub Markdown、图片、链接和代码；仓库内链接原位导航，外部链接使用应用内浏览器。
- **Agent**：分别配置项目 Agent 与翻译执行器，支持 Codex CLI、Claude Code、Gemini CLI、OpenCode 和自定义 CLI；两条执行通道互不阻塞。
- **提交起草**：从当前项目的真实暂存 Diff 起草简洁或完整提交信息，可直接提交并推送或重新起草。
- **错误诊断**：完整展示 Git 输出、应用错误代码、退出代码、仓库和脱敏后的诊断信息。
- **应用内更新**：更新中心直接读取 GitHub Releases 的版本与更新日志；GitHub Appcast 负责下载和安装发布包，发布页在应用内打开。
- **本地化与外观**：简体中文和英文、浅色和深色外观、默认专业主题、轻毛玻璃主题与可配置强调色。

## 环境

- macOS 14 或更高版本
- Xcode 26 或 Swift 6.1 工具链
- Git 2.30 或更高版本
- GitHub 功能需要 [GitHub CLI](https://cli.github.com/)；GitGatto 复用其现有登录，不读取令牌
- Agent 功能需要至少一个已安装并完成登录的受支持 CLI

## 开发

```bash
cd /Users/linchengbo/Documents/GitGatto
swift run GitGatto
```

直接打开仓库：

```bash
swift run GitGatto --repository /path/to/repository
```

运行测试：

```bash
swift test
```

生成稳定路径的 macOS 应用包：

```bash
./scripts/package-macos.sh
open dist/GitGatto.app
```

脚本始终替换 `dist/GitGatto.app`，不会按版本创建输出目录。发布包与更新源配置见 [发布与更新](docs/RELEASING.md)。

## 项目结构

```text
Assets/                    品牌矢量源与应用图标
Sources/GitGatto/App       应用入口与窗口
Sources/GitGatto/Models    领域模型与持久状态
Sources/GitGatto/Services  Git、GitHub、Agent、扫描与更新服务
Sources/GitGatto/Views     macOS SwiftUI 界面
Sources/GitGatto/Resources 本地化、品牌资源与协议文档
Tests/GitGattoTests        行为测试
scripts/                   构建与打包脚本
docs/                      架构、贡献、文档与发布规则
```

## 文档

- [产品约束](PRODUCT.md)
- [设计系统](DESIGN.md)
- [架构](docs/ARCHITECTURE.md)
- [贡献指南](CONTRIBUTING.md)
- [文档规则](docs/DOCUMENTATION.md)
- [发布与更新](docs/RELEASING.md)
- [更新日志](CHANGELOG.md)
- [安全策略](SECURITY.md)
- [第三方许可](THIRD_PARTY_NOTICES.md)

## 数据与凭据

GitGatto 的设置、Agent 对话、操作记录和文档译文默认保存在本机。Git、SSH、GitHub CLI 与 Agent CLI 继续使用各自的系统凭据来源；应用不读取、显示或保存令牌、密码和私钥。远端写入只由明确的用户操作触发。

## 许可与开发者

GitGatto 由 **ZIJIU522** 开发，采用 [MIT License](LICENSE)。第三方组件归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
