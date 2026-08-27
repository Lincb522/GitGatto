# 架构

## 运行边界

GitGatto 是 macOS 14 及以上版本的 SwiftUI 应用。界面状态由 `WorkspaceViewModel` 统一持有，Git、GitHub、Agent、项目扫描和应用更新通过独立服务执行。用户选择的仓库是所有本地操作的唯一工作目录。

## 主要模块

- `GitRepositoryService`：通过参数数组调用本机 Git，读取状态、Diff、历史、分支和上游计数，并执行用户触发的写入。
- `GitHubService`：通过 GitHub CLI 标准凭据调用 API、Fork 与克隆；令牌不进入应用进程的展示与持久层。
- `CodexService`：项目 Agent 与翻译各有独立配置、进程和取消通道；自定义 CLI 模板只展开受支持的参数占位符。
- `RepositoryDiscoveryService`：仅在用户手动发起后扫描；结果必须是当前用户可读写并可管理的 Git 仓库，添加由用户逐项确认。
- `AppUpdateManager`：包装 Sparkle 更新器。只有 `SUFeedURL` 使用 HTTPS 且应用包含 `SUPublicEDKey` 时才启动更新通道。
- `GlobalErrorHandler`：把 Git、GitHub、Agent 与系统故障归一为稳定错误报告，并在显示前脱敏。

## 状态与持久化

- 仓库快照、暂存状态和同步计数由当前仓库的实时读取刷新。
- 最近仓库、设置、Agent 对话、操作记录和文档译文保存在本机应用支持目录。
- 移除侧边栏项目只移除目录记录，不删除磁盘仓库。
- Agent 起草不会写入 Git；提交、推送、Fork 和发布回复由用户再次触发。

## 更新流程

1. 更新中心请求 HTTPS Appcast。
2. Sparkle 比较版本和构建号。
3. 下载包通过 EdDSA 公钥验证。
4. 标准安装器显示发布信息并请求用户确认。
5. 安装完成后重新启动 GitGatto。

签名私钥不属于应用运行时或仓库内容。发布配置见 [RELEASING.md](RELEASING.md)。
