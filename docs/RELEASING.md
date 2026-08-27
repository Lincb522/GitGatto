# 发布与应用内更新

GitGatto 使用 GitHub Releases 作为唯一发布源，并使用 Sparkle 2.9.4 完成下载、签名验证、安装和重新启动。更新中心通过 GitHub Releases API 展示版本历史与 Markdown 更新日志。

## 版本

发布前同步修改：

- `scripts/package-macos.sh` 中的 `VERSION` 与 `BUILD`
- `AppUpdateManager` 在 Swift Package 调试运行时使用的回退版本
- `CHANGELOG.md`、两种语言的 `ReleaseNotes.md` 与 GitHub Release 说明

构建号必须递增。

## 更新签名

使用 Sparkle 提供的 `generate_keys` 创建 EdDSA 密钥。私钥由发布者控制并保存在其正常安全存储中；不得提交到仓库、写入应用包或输出到日志。

打包时只传入公钥：

```bash
GITGATTO_UPDATE_PUBLIC_KEY='PUBLIC_KEY' \
GITGATTO_CODESIGN_IDENTITY='Developer ID Application: …' \
./scripts/package-macos.sh
```

`GITGATTO_UPDATE_PUBLIC_KEY` 未设置时仍能生成开发包，但更新中心会明确显示“尚未配置更新通道”，不会启动不受签名保护的更新。

安装更新源固定指向 GitHub Release 附件：

```text
https://github.com/Lincb522/GitGatto/releases/latest/download/appcast.xml
```

开发或镜像验证可用 `GITGATTO_UPDATE_FEED_URL` 覆盖；脚本拒绝非 HTTPS 地址。应用内更新日志使用：

```text
https://api.github.com/repos/Lincb522/GitGatto/releases?per_page=10
```

## 生成发布包

```bash
./scripts/package-macos.sh
mkdir -p dist/releases
ditto -c -k --keepParent dist/GitGatto.app dist/releases/GitGatto-0.14.0.zip
cp Sources/GitGatto/Resources/zh-Hans.lproj/ReleaseNotes.md \
  dist/releases/GitGatto-0.14.0.md
```

脚本输出固定为 `dist/GitGatto.app`，使用临时目录完成构建与验证后再替换现有应用包。

## 生成 Appcast

在包含签名 ZIP 和同名 Markdown 发布说明的目录运行 Sparkle 的 `generate_appcast`。工具会把 Markdown 写入 Appcast；下载地址直接指向当前 GitHub Release：

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --embed-release-notes \
  --download-url-prefix "https://github.com/Lincb522/GitGatto/releases/download/v0.14.0/" \
  --full-release-notes-url "https://github.com/Lincb522/GitGatto/releases" \
  dist/releases
```

生成后创建 `v0.14.0` GitHub Release，正文使用该版本的更新日志，并上传：

- `GitGatto-0.14.0.zip`
- `appcast.xml`
- 生成的增量更新文件（如有）

旧版本通过 `releases/latest/download/appcast.xml` 跟随最新正式 Release。草稿和预发布版本不会成为稳定通道的 `latest` Release。

发布前检查：

- GitHub Release 已公开，Appcast 与 ZIP 可通过 HTTPS 匿名读取。
- Appcast 版本、构建号、下载地址与发布说明正确。
- ZIP 的 EdDSA 签名可由应用包内的 `SUPublicEDKey` 验证。
- 使用正式 Developer ID 签名并完成公证。
- 在上一正式版本中完成“读取 GitHub 更新日志 → 检查 → 下载 → 安装 → 重新启动”的升级验证。
- 更新前后的本地仓库、设置、Agent 对话和译文保持可用。

仓库未公开或尚无正式 GitHub Release 时，应用显示包内更新记录；不得将未签名附件作为安装更新提供。
