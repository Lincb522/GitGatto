# 贡献指南

## 开始

1. 使用 macOS 14 及以上版本和项目声明的 Swift 工具链。
2. 从仓库根目录运行 `swift package resolve`。
3. 直接打开 `GitGatto.xcodeproj`，或使用 `swift run GitGatto` 启动应用。
4. 工程结构以 `project.yml` 为准，修改后运行 `./scripts/generate-xcodeproj.sh`，不要手动编辑生成的 `project.pbxproj`。
5. 使用共享的 `GitGatto` scheme 或 `swift test` 验证行为。

## 修改范围

- 保持 Git、GitHub、Agent、翻译和更新服务与 SwiftUI 视图分离。
- 用户可见文本必须同时加入英文与简体中文本地化。
- Git 与 CLI 命令使用参数数组执行，不拼接 Shell 字符串。
- 远端写入必须来自明确的用户操作；读取状态不得隐式 Pull、Push、Fork、评论或合并。
- 不读取、打印或持久化 GitHub、SSH、Agent 与更新签名私钥。
- UI 修改必须检查浅色、深色、窗口最小尺寸、长文本、加载、空状态和错误状态。

## 提交前

- 运行 `swift test`。
- 修改用户行为时同步更新 `README.md`、`PRODUCT.md`、应用内帮助或协议中的相关事实。
- 修改 README 中的功能、依赖、权限或版本事实时，同步更新根目录中的全部语言版本；各版本必须保留相同的功能范围和语言切换入口。
- 新增带日期的版本记录后运行 `./scripts/generate-update-curve.py`，并核对 `docs/UPDATE_HISTORY.md` 中的日期、版本和累计数量。
- 修改路线或架构时运行 `./scripts/generate-document-diagrams.py`，确保文档引用的 SVG 与正文一致。
- 修改依赖时更新 `Package.resolved` 与 `THIRD_PARTY_NOTICES.md`。
- 不提交 `.build`、`dist`、本机设置、凭据或调试数据。

详细架构与文档要求见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 和 [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)。
