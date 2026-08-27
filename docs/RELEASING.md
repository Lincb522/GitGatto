# 发布与应用内更新

GitGatto 使用 Sparkle 2.9.4 提供应⽤内更新。更新中心是应用内入口；下载、签名验证、安装和重新启动由 Sparkle 的标准更新流程完成。

## 版本

发布前同步修改：

- `scripts/package-macos.sh` 中的 `VERSION` 与 `BUILD`
- `AppUpdateManager` 在 Swift Package 调试运行时使用的回退版本
- 发布说明与 Appcast 条目

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

更新源默认使用：

```text
https://raw.githubusercontent.com/ZIJIU522/GitGatto/main/appcast.xml
```

发布仓库确定后可用 `GITGATTO_UPDATE_FEED_URL` 覆盖；脚本拒绝非 HTTPS 地址。

## 生成发布包

```bash
./scripts/package-macos.sh
mkdir -p dist/releases
ditto -c -k --keepParent dist/GitGatto.app dist/releases/GitGatto-0.14.0.zip
```

脚本输出固定为 `dist/GitGatto.app`，使用临时目录完成构建与验证后再替换现有应用包。

## 生成 Appcast

在包含签名 ZIP 的目录运行 Sparkle 的 `generate_appcast`。工具位于 Swift Package 下载的 Sparkle 工具目录：

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_appcast dist/releases
```

发布前检查：

- Appcast 与 ZIP 使用 HTTPS 可访问。
- Appcast 版本、构建号、下载地址与发布说明正确。
- ZIP 的 EdDSA 签名可由应用包内的 `SUPublicEDKey` 验证。
- 使用正式 Developer ID 签名并完成公证。
- 在上一正式版本中完成“检查 → 下载 → 安装 → 重新启动”的升级验证。
- 更新前后的本地仓库、设置、Agent 对话和译文保持可用。

当前开源与官网地址尚未发布；启用正式更新源前必须先完成地址发布和真实升级验证。
