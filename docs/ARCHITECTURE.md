# 架构

## 运行边界

GitGatto 是 macOS 14 及以上版本的 SwiftUI 应用。界面状态由 `WorkspaceViewModel` 统一持有，Git、GitHub、Agent、项目扫描和应用更新通过独立服务执行。用户选择的仓库是所有本地操作的唯一工作目录。

## 主要模块

- `GitRepositoryService`：通过参数数组调用本机 Git，读取状态、Diff、历史、分支和上游计数，并执行用户触发的写入。
- `GitHubService`：通过 GitHub CLI 标准凭据调用 API、Fork 与克隆；令牌不进入应用进程的展示与持久层。
- `CodexService`：项目 Agent 与翻译各有独立配置、进程和取消通道；自定义 CLI 模板只展开受支持的参数占位符。
- `RepositoryDiscoveryService`：仅在用户手动发起后扫描；结果必须是当前用户可读写并可管理的 Git 仓库，添加由用户逐项确认。
- `GitHubReleaseService`：通过 GitHub Releases API 读取正式版本、发布日期和 Markdown 更新日志，不接触 GitHub 凭据。
- `AppUpdateManager`：合并 GitHub 发布记录与 Sparkle 安装状态。`SUFeedURL` 使用 HTTPS 时启动安装通道。
- `GlobalErrorHandler`：把 Git、GitHub、Agent 与系统故障归一为稳定错误报告，并在显示前脱敏。

## 状态与持久化

- 仓库快照、暂存状态和同步计数由当前仓库的实时读取刷新。
- 最近仓库、设置、Agent 对话、操作记录和文档译文保存在本机应用支持目录。
- 移除侧边栏项目只移除目录记录，不删除磁盘仓库。
- Agent 起草在暂存区为空时会暂存当前改动；已有暂存内容时保持原边界。提交、推送、Fork 和发布回复由用户再次触发。

## 工程入口

- `GitGatto.xcodeproj` 提供应用与测试目标、共享 scheme、Sparkle 依赖和资源构建设置。
- `project.yml` 是 Xcode 工程结构的唯一编辑源，`scripts/generate-xcodeproj.sh` 负责生成工程文件。
- `Package.swift` 保持同一源码与依赖的命令行构建入口；`AppResourceBundle` 统一解析 Xcode 主 Bundle、SwiftPM 资源 Bundle 与发行包资源。
- `GattoIconAssets` 从应用资源 Bundle 加载 GitGatto 专属 PNG 图标，以模板色和目标点尺寸渲染；设计源、语义顺序与生成脚本位于 `docs/icon-system/image2-all-icons` 和 `scripts/build-image2-icons.py`。

## 更新流程

1. 更新中心从 `Lincb522/GitGatto` 的 GitHub Releases API 读取版本记录和更新日志。
2. Sparkle 从 GitHub Release 的 `appcast.xml` 检查版本与构建号。
3. GitHub Release 提供经 Developer ID 签名并完成 Apple 公证的 DMG。
4. Sparkle 读取 DMG，并检查新旧应用的代码签名要求一致。
5. 标准安装器显示同一版本的发布信息并请求用户确认。
6. 安装完成后重新启动 GitGatto。

发布配置见 [RELEASING.md](RELEASING.md)。
