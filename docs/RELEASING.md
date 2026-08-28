# 发布与应用内更新

GitGatto 使用 GitHub Releases 作为唯一发布源，并使用 Sparkle 2.9.4 完成下载、安装和重新启动。更新中心通过 GitHub Releases API 展示版本历史与 Markdown 更新日志。

## GitHub Actions 凭据

正式发布由 `.github/workflows/release-macos.yml` 完成。仓库的 Actions Secrets 必须包含：

- `MACOS_DEVELOPER_ID_P12_BASE64`：包含私钥的 Developer ID Application `.p12` 文件的 Base64 内容
- `APP_STORE_CONNECT_KEY_ID`：公证 API Key ID
- `APP_STORE_CONNECT_ISSUER_ID`：App Store Connect Issuer ID
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`：公证 API Key `.p8` 文件的 Base64 内容

`.cer` 只包含公钥证书，不能用于 CI 签名。`.p12` 必须同时包含 Developer ID Application 证书与对应私钥。Team ID 与签名身份已固定为 `7VJKFX4HF8` 和 `Developer ID Application: chengbo lin (7VJKFX4HF8)`。

GitHub Actions 在临时钥匙串中导入证书，并使用 App Store Connect API Key 公证。临时钥匙串和运行器文件会在任务结束后销毁，私钥不会写入仓库或构建产物。

## 版本

正式标签使用 `vMajor.Minor.Patch`。工作流从标签生成应用版本，并使用版本号生成递增构建号。发布前更新 `CHANGELOG.md`、两种语言的 `ReleaseNotes.md` 与应用内相关版本回退值。

## 更新地址

安装更新源固定指向 GitHub Release 附件：

```text
https://github.com/Lincb522/GitGatto/releases/latest/download/appcast.xml
```

开发或镜像验证可用 `GITGATTO_UPDATE_FEED_URL` 覆盖；脚本拒绝非 HTTPS 地址。应用内更新日志使用：

```text
https://api.github.com/repos/Lincb522/GitGatto/releases?per_page=10
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
git tag v0.15.0
git push origin v0.15.0
```

工作流按顺序执行：

1. 测试并构建通用架构应用。
2. 使用 Developer ID Application 签名应用及 Sparkle 嵌套组件。
3. 将应用提交 Apple 公证并装订票据。
4. 创建、签名并公证 `GitGatto-<version>.dmg`，再装订 DMG 票据。
5. 从 DMG 生成 `appcast.xml`。
6. 创建或更新 GitHub Release，上传 DMG、Appcast、更新说明与 SHA-256 文件。

旧版本通过 `releases/latest/download/appcast.xml` 跟随最新正式 Release。草稿和预发布版本不会成为稳定通道的 `latest` Release。

发布前检查：

- GitHub Release 已公开，Appcast 与 DMG 可通过 HTTPS 匿名读取。
- Appcast 版本、构建号、下载地址与发布说明正确。
- DMG 包含完整的 `GitGatto.app` 与“应用程序”入口，应用标识保持为 `dev.gitgatto.client`。
- 应用和 DMG 的 Developer ID 签名、公证票据、Gatekeeper 评估与磁盘映像校验全部通过。
- 在上一正式版本中完成“读取 GitHub 更新日志 → 检查 → 下载 → 安装 → 重新启动”的升级验证。
- 更新前后的本地仓库、设置、Agent 对话和译文保持可用。

仓库尚无正式 GitHub Release 时，应用显示包内更新记录。
