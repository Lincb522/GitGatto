# 发布与应用内更新

GitGatto 使用 GitHub Releases 作为唯一发布源，并使用 Sparkle 2.9.6 完成下载、安装和重新启动。更新中心通过 GitHub Releases API 展示版本历史与 Markdown 更新日志。

## 持续集成

`.github/workflows/ci.yml` 在推送到 `main` 与 Pull Request 时执行 `swift build --build-tests`、`swift test` 和一次临时签名打包。发布工作流不重复运行测试，请确保发布标签指向的提交已通过 CI。

CI 与正式发布固定使用 Xcode 26.0，与 `project.yml` 保持一致，不使用运行器默认的 Xcode 16.4。最低系统版本仍为 macOS 14；Swift 6.1.2 在当前模型默认参数的 SIL 生成阶段会崩溃。

## GitHub Actions 凭据

正式发布由 `.github/workflows/release-macos.yml` 完成。

必需的 Actions Secrets：

| 名称 | 内容 |
| --- | --- |
| `MACOS_DEVELOPER_ID_P12_BASE64` | 包含私钥的 Developer ID Application `.p12` 文件的 Base64 内容 |
| `MACOS_DEVELOPER_ID_P12_PASSWORD` | 导出该 `.p12` 时设置的口令 |

可选的 Apple 公证凭据（三项必须同时配置）。公证仅在手动运行工作流并选择 `notarize` 时执行；标签推送发布默认只做签名：

| 名称 | 内容 |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API 密钥 ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect Issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` | `AuthKey_<KEY_ID>.p8` 的 Base64 内容 |

Sparkle EdDSA 签名为正式发布的必需配置（两项必须同时配置）：

| 名称 | 类型 | 内容 |
| --- | --- | --- |
| `SPARKLE_ED_PRIVATE_KEY` | Secret | `generate_keys -x key.txt` 导出的私钥文件内容 |
| `SPARKLE_ED_PUBLIC_KEY` | Variable | `generate_keys -p` 打印的公钥 |

生成方式（Sparkle 工具位于 `.build/artifacts/sparkle/Sparkle/bin`）：

```bash
swift package resolve
BIN=$(find .build/artifacts/sparkle/Sparkle/bin -maxdepth 1 -name generate_keys)
"$BIN"              # 在本机钥匙串生成密钥并打印公钥
"$BIN" -x key.txt   # 导出私钥文件，用于 Secret；导出后妥善保管并删除本地副本
```

公钥保存在 `Config/GitGatto-Info.plist` 的 `SUPublicEDKey`，本地打包与 Xcode 构建共用。GitHub Variable 必须与其一致；私钥只保存在钥匙串和 GitHub Secret，不得提交到仓库。已有密钥时不要重新生成或替换。

正式发布缺少任一密钥时立即停止；生成 Appcast 后，使用应用内公钥验证 DMG 的 Ed25519 签名、长度和版本，验证通过后才上传。签名证书和 EdDSA 密钥不能在同一次更新中一起更换。

`.cer` 只包含公钥证书，不能用于 CI 签名。`.p12` 必须同时包含 Developer ID Application 证书与对应私钥。Team ID 与签名身份已固定为 `7VJKFX4HF8` 和 `Developer ID Application: chengbo lin (7VJKFX4HF8)`。

GitHub Actions 在临时钥匙串中导入证书。临时钥匙串和运行器文件会在任务结束后销毁，私钥不会写入仓库或构建产物。

## 版本

正式标签使用 `vMajor.Minor.Patch`。工作流从标签生成应用版本，并使用版本号生成递增构建号。本地打包时默认版本与构建号从 `project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 读取。

发布前更新：

- `project.yml` 中的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`，然后运行 `./scripts/generate-xcodeproj.sh`
- `CHANGELOG.md`
- 两种语言的 `ReleaseNotes.md`
- `Sources/GitGatto/Services/AppUpdateManager.swift` 中的版本回退值（仅在没有 Info.plist 的 `swift run` 场景使用）

## 权限与 Entitlements

应用启用 Hardened Runtime，签名时附带 `Config/GitGatto.entitlements`：

- `com.apple.security.automation.apple-events`：GitHub 登录通过 `osascript` 打开 Terminal 运行 `gh auth login`，没有该 entitlement 时系统会静默拒绝。

对应的用途说明 `NSAppleEventsUsageDescription` 同时写在 `Config/GitGatto-Info.plist` 与 `scripts/package-macos.sh` 中，两处需保持一致。

## 更新地址

安装更新源固定指向 GitHub Release 附件：

```text
https://github.com/Lincb522/GitGatto/releases/latest/download/appcast.xml
```

开发或镜像验证可用 `GITGATTO_UPDATE_FEED_URL` 覆盖；脚本拒绝非 HTTPS 地址。应用内更新日志使用：

```text
https://api.github.com/repos/Lincb522/GitGatto/releases?per_page=100
```

## 本地构建

```bash
./scripts/package-macos.sh
./scripts/create-dmg.sh dist/GitGatto.app dist/GitGatto.dmg
```

未设置 `GITGATTO_CODESIGN_IDENTITY` 时，本地应用使用临时签名，适合开发验证。正式工作流使用 Developer ID Application 签名所有 Sparkle 嵌套组件与应用主包，并启用 Hardened Runtime 和安全时间戳。

## 正式发布

完成发布说明后创建并推送标签：

```bash
git tag v0.18.27
git push origin v0.18.27
```

工作流按顺序执行：

1. 校验 Secrets、标签格式和公钥一致性；公证须明确选择。
2. 构建通用架构应用，使用 Developer ID Application 签名应用及 Sparkle 嵌套组件。
3. 明确选择公证且凭据完整时，公证并装订应用和 DMG；未选择公证时只创建并签名 DMG。
4. 从 DMG 生成带 `sparkle:edSignature` 的 `appcast.xml`，再验证签名、长度和版本。
5. 创建或更新 GitHub Release，上传 DMG、Appcast、更新说明与 SHA-256 文件。

旧版本通过 `releases/latest/download/appcast.xml` 跟随最新正式 Release。草稿和预发布版本不会成为稳定通道的 `latest` Release。

`.github/workflows/notarize-macos.yml` 仍可用于对已有标签单独补做公证并把结果作为 Actions 产物下载，例如公证凭据在发布之后才配置好的情况。

发布前检查：

- GitHub Release 已公开，Appcast 与 DMG 可通过 HTTPS 匿名读取。
- Appcast 版本、构建号、下载地址与发布说明正确。
- DMG 包含完整的 `GitGatto.app` 与“应用程序”入口，应用标识保持为 `dev.gitgatto.client`。
- 应用和 DMG 的 Developer ID 签名与磁盘映像校验全部通过；已公证时 `spctl --assess` 应返回 accepted。
- 在上一正式版本中完成“读取 GitHub 更新日志 → 检查 → 下载 → 安装 → 重新启动”的升级验证。
- 更新前后的本地仓库、设置、Agent 对话和译文保持可用。

仓库尚无正式 GitHub Release 时，应用显示包内更新记录。

## 后台监控助手

应用包包含 `Contents/Library/LoginItems/GitGattoMonitor.app`，标识为 `dev.gitgatto.monitor`。主程序与助手共用监控实现；助手使用独立进程入口，只创建状态栏面板，不启动主窗口或更新器。主程序打开时，监控和状态栏由主程序负责；退出后由助手接管。状态栏显示与退出后继续监控是两个独立选项。

`scripts/embed-monitor-helper.sh` 在 SwiftPM 打包和 Xcode 构建中嵌入助手，并复制所需资源、框架和 Xcode Debug 配套运行库。签名顺序为框架、助手内运行库、助手、主应用；正式包的助手与主应用必须使用同一 Developer ID 签名。不要只替换主程序二进制而遗漏助手。

发布前还需验证：

- 助手版本、构建号和最低系统版本与主应用一致，内外包均通过 `codesign --verify --deep --strict`。
- 在设置中启用“退出后继续监控”，检查系统注册状态；需要批准时，由用户在系统设置中允许后台运行。
- 完全退出主应用后，对测试仓库进行改动，验证状态栏状态、活动记录和恢复点；重新打开主应用后，确认助手停止扫描并交还监控所有权。
- 更新已启用后台监控的旧版本，验证旧助手注销、新助手注册及退出后的接管；关闭该选项后，验证系统后台项目注销。

后台监控默认关闭。登录项目受 macOS 的用户授权控制；休眠、关机和退出系统登录期间不会运行监控。
