# 发布与应用内更新

GitGatto 使用 GitHub Releases 作为唯一发布源，并使用 Sparkle 2.9.6 完成下载、安装和重新启动。更新中心通过 GitHub Releases API 展示版本历史与 Markdown 更新日志。

## 持续集成

`.github/workflows/ci.yml` 在推送到 `main` 与 Pull Request 时执行 `swift build --build-tests`、`swift test` 和一次临时签名打包。发布工作流不重复运行测试，请确保发布标签指向的提交已通过 CI。

## GitHub Actions 凭据

正式发布由 `.github/workflows/release-macos.yml` 完成。

必需的 Actions Secrets：

| 名称 | 内容 |
| --- | --- |
| `MACOS_DEVELOPER_ID_P12_BASE64` | 包含私钥的 Developer ID Application `.p12` 文件的 Base64 内容 |
| `MACOS_DEVELOPER_ID_P12_PASSWORD` | 导出该 `.p12` 时设置的口令 |

可选的 Apple 公证凭据（三项必须同时配置，配置后 Release DMG 会自动公证并装订票据；缺失时工作流输出警告并只做签名）：

| 名称 | 内容 |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API 密钥 ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect Issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` | `AuthKey_<KEY_ID>.p8` 的 Base64 内容 |

可选的 Sparkle EdDSA 签名（两项必须同时配置）：

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

配置后，打包脚本会把公钥写入 `SUPublicEDKey`，`generate_appcast` 会为 DMG 附加 `sparkle:edSignature`。未配置时 Sparkle 只依赖 Developer ID 签名的一致性验证更新；更换证书会导致已安装用户无法更新，因此建议尽早启用。**密钥一经发布不要更换**：Sparkle 只允许在证书和 EdDSA 密钥中轮换其一。

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
git tag v0.18.17
git push origin v0.18.17
```

工作流按顺序执行：

1. 校验 Secrets、标签格式，并根据已配置的凭据决定是否公证、是否签名 Appcast。
2. 构建通用架构应用，使用 Developer ID Application 签名应用及 Sparkle 嵌套组件。
3. 已配置公证凭据时：公证并装订应用，创建 DMG，再公证并装订 DMG；否则只创建并签名 DMG。
4. 从 DMG 生成 `appcast.xml`（已配置 EdDSA 时附带 `sparkle:edSignature`）。
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
