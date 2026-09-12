<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">macOS · Git · GitHub</p>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.pt-BR.md">Português</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.ar.md">العربية</a>
</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon 與 Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://gatto.zijiu522.cn">官網</a>
  ·
  <a href="https://github.com/Lincb522/GitGatto/releases/latest">下載</a>
  ·
  <a href="CHANGELOG.md">版本記錄</a>
  ·
  <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a>
</p>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/media/github-project.png" alt="GitHub 專案"><br><sub><b>GitHub 專案</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/workspace.png" alt="工作區與 Diff"><br><sub><b>工作區與 Diff</b></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="docs/media/recovery-center.png" alt="災備中心"><br><sub><b>災備中心</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/file-time-machine.png" alt="文件時間機器"><br><sub><b>文件時間機器</b></sub></td>
  </tr>
</table>

截圖使用示範資料展示介面，專案名稱與計數不代表實際使用指標。

GitGatto 是 macOS 原生 Git 與 GitHub 客戶端，支持 Apple Silicon 和 Intel。除了日常倉庫操作，還提供未提交代碼備份、外部 Agent 活動記錄、目標交付、回歸定位和開發環境安裝。

<a id="why"></a>
## 為什麼做 GitGatto

寫 GitGatto，是因為寫完代碼以後的事情同樣費時間：整理一堆混在一起的改動，查一個回歸從哪次提交開始，等 CI、審 PR、發版本。臨時切換任務還容易弄丟草稿和未提交文件。

用了 Agent 以後，又多了幾個實際問題：它改了什麼、為什麼這樣改、失敗時留下了什麼，以及它說“完成”之後結果到底能不能用。我們想把這些事做好，而不是只給 Git 命令套一層按鈕。GitGatto 繼續使用系統 Git 和本機 CLI，讓改動、證據、恢復點和後續操作都能查到。

[災備與保護](#recovery) · [狀態欄監控](#monitoring) · [目標交付](#goals) · [變更編排](#intent) · [回歸取證](#regression) · [項目工具](#project-tools) · [安裝與配置](#install-tools)

<a id="features"></a>
## 特色功能

<a id="recovery"></a>
### 未提交代碼的災備，與外部 Agent 保護

災備中心為加入 GitGatto 的本機倉庫保存 Git bundle 與未提交檔案。定時及重大改動備份略過未變內容，也可手動建立恢復點；每個倉庫最多輪換保留三份。

應用內 Agent 寫入前可建立恢復點。倉庫守衛觀察外部 Agent、終端及腳本造成的刪除、未提交內容遺失、引用回退及倉庫不可用，列出原因與路徑。支援檢查及比對備份檔案、匯出所選檔案、恢復至新目錄；更換備份位置會遷移既有內容。

斷電與異常退出依最近完整恢復點處理：內容與清單先同步至磁碟，再寫入並同步完成標記，最後輪換舊備份。下次啟動處理中斷的寫入。保護範圍限於已儲存至磁碟且成功備份的內容；之後的修改、編輯器未儲存內容及排除檔案不保證可恢復。守衛偵測變化，不攔截其他應用的每一道命令。

<a id="monitoring"></a>
### 不打開主窗口，也能看倉庫情況

狀態列可獨立選擇全部或單一倉庫，查看改動、上游同步、恢復點、Actions、目標及每日活動。收起時顯示倉庫範圍、改動數與提醒；展開面板可捲動並沿用主程式主題。活動統計記錄提交與偵測到的變化，不計工時。

在設定開啟「退出後繼續監控」後，獨立背景助手在主程式退出時接手監控，並依保護設定執行定時備份、重大改動備份及倉庫守衛。重新開啟主程式會交回任務，避免重複掃描。背景執行預設關閉，必要時須由 macOS 授權。

總開關、各通道、狀態列顯示及間隔皆在設定中。隱藏狀態列不會關閉已啟用的背景災備；關閉監控總開關或倉庫保護則停止對應任務。

<a id="goals"></a>
### 把交付過程保存成可繼續的目標

目標可直接選擇「提交並推送」「建立 PR」「發布版本」或「自訂」，也可從改動、Issue、PR 及失敗檢查建立。優先顯示目前進度，詳細步驟與歷史按需展開。

根據所選流程，逐項核對暫存、提交、Push、PR、Review、Actions、構建產物、Release、DMG、Appcast 和本機版本。自定義目標由 Agent 生成候選條件，確認後才執行。中斷後重新讀取實際狀態再繼續，不把 Agent 的文字回復當成成功結果；合併、發佈標籤和安裝仍有單獨確認。

<a id="intent"></a>
### 把混在一起的改動拆成提交

變更中心按文件或 Diff 分塊分組，可以分別寫提交說明，也可以讓 Agent 整理分組。執行前檢查是否遺漏、重復分配，以及倉庫是否已經變化，再創建恢復點並按順序提交。

每個提交會運行差異檢查或指定的驗證命令。中途失敗會嘗試回退原 HEAD 和暫存邊界；恢復點仍可用於檢查，不承諾任何錯誤下都能自動回退成功。

<a id="regression"></a>
### 在獨立工作樹里定位回歸

回歸取證用 `git bisect` 縮小首個故障提交的範圍，不切換正在工作的目錄。自動模式運行驗證命令；手動模式把候選標為正常、故障或跳過。提交、判定、退出碼、耗時和輸出隨任務保存。

定位後可把證據交給 Agent 修復、復驗並準備 PR。驗證命令必須能判斷你要找的問題，跳過太多提交時不一定能得到唯一結論。

<a id="evidence"></a>
### 代碼緣由、故障膠囊與活動記錄

- **代碼緣由**：從文件行追溯提交，在 GitHub CLI 可用時繼續查看關聯 PR、Issue、Review 和 Checks。
- **故障膠囊**：把基準提交、補丁、允許收錄的未跟蹤文件、失敗命令、輸出和工具版本導出為 `.gatto`。導入時校驗結構與摘要，再在獨立工作樹恢復；不會自動執行包里的命令。只過濾已知敏感路徑和可識別內容，分享前仍需檢查。
- **外部 Agent 活動記錄**：將文件和 Git 引用變化，與當時工作目錄位於倉庫中的已知 Agent 進程關聯，顯示證據強度。進程恰好在運行，不等於能證明每次改動都是它造成的。

<a id="agent"></a>
### Agent 不只起草提交說明

支持 Codex CLI、Claude Code、Gemini CLI、OpenCode、DeepSeek Harness（dsh）、Cursor Agent、GitHub Copilot CLI、Qwen Code 和自定義 CLI。內置 Git 處理指引覆蓋暫存審閱、提交起草、衝突、分支整理、歷史恢復、倉庫健康和發佈檢查，也可攜帶 Git LFS、hooks、簽名或同步失敗的原始輸出繼續排查。

項目處理、翻譯、搜索和安裝有獨立執行通道。README 重寫先預覽再應用；Issue 和 PR 回復根據討論與差異起草，可編輯，確認後才發送。

也可直接設定 OpenAI 相容 API 或 DeepSeek API，API 模式無須安裝 CLI。專案與翻譯可分別選擇介面及模型，支援模型清單、能力檢查與串流回覆；金鑰存於系統鑰匙圈。API Agent 可讀取專案、執行命令及在受控範圍寫入；翻譯通道不提供專案寫入工具。

<a id="project-tools"></a>
### 切換任務時，保存的不只是分支

**工作現場**可保存暫存與未暫存改動、未跟蹤文件、分支、草稿、所選文件及關聯目標和鏈接。恢復時核對倉庫狀態；也可以在獨立工作樹中打開。被忽略文件不在保存範圍，現場不是獨立備份。

| 工具 | 能做什麼 |
| --- | --- |
| 代碼搜索 | 跨已管理倉庫搜索當前文件、指定版本或歷史改動；按目錄、語言、擴展名篩選，預覽後把證據交給 Agent。普通文本匹配，結果有數量限制。 |
| 運行命令 | 讀取項目腳本或添加自定義命令，固定常用項，查看實時輸出、耗時和退出狀態，支持停止、重試與打開本地服務。非交互執行，參數使用 JSON 數組。 |
| 忽略規則 | 查明規則來源，預覽後編輯共享 `.gitignore` 或本地 `.git/info/exclude`；停止跟蹤時保留磁盤文件。 |
| 提交身份 | 按倉庫或目錄綁定作者與簽名配置，查看生效來源，提交前檢查身份一致性。Git 作者身份與 GitHub 登錄分開管理。 |

從頂部“項目工具”或 `⌘K` 進入。

<a id="install-tools"></a>
### 安裝之後，把配置和驗證一起做完

應用倉庫從 GitHub Releases 查找版本和安裝包，區分下載與安裝。DMG、ZIP 使用本機安裝流程，需要命令行的交給 Agent；下載管理顯示階段、輸出和重試入口。

開發工具庫包含 **99 種工具與運行庫**，可檢測本機版本、多選或批量升級。安裝與升級有各自隊列，最多三路任務並行；Homebrew 寫入串行調度，避免同時修改依賴。

安裝任務繼續處理需要的 PATH、插件註冊、初始化和配置遷移，再檢查可執行文件與實際版本。下載成功、Agent 說完成，都不能代替本機驗證。缺少權限或配置時保留待處理事項；賬號登錄、系統授權仍需本人完成。“已安裝”應用列表記錄 GitGatto 的安裝結果，不是整機應用清單。

<a id="git-github"></a>
## Git 與 GitHub 的日常操作

- **工作區與歷史**：暫存、提交、Diff、提交圖、Blame、文件歷史和歷史媒體預覽；組合搜索 SHA、作者、路徑、文本、日期和引用。
- **分支與恢復**：分支、標籤、遠程、貯藏、工作樹、引用比較、Reflog 恢復分支；整理提交支持重排、合併、拆分、修訂、揀選、撤銷和重置。歷史重寫會檢查已發佈提交，破壞性操作需要確認。
- **衝突與診斷**：編輯合併、變基或貯藏衝突，繼續、跳過或中止 Git 操作；檢查 Git LFS、hooks 和工具環境。
- **多倉庫同步**：批量獲取、拉取和推送，分別顯示領先、落後、分叉、衝突和失敗，可重試失敗項。
- **GitHub 項目**：賬號倉庫、倉庫與開發者搜索、自然語言檢索、Star、Fork、克隆；應用內瀏覽代碼、README、Release 和附件。
- **收件箱、Issue 與 PR**：篩選待審閱、提及、檢查失敗等事項；創建和處理 Issue；PR 文件審閱、已查看標記、行評論、回復與 Review。
- **Actions**：查看運行和日誌、重新運行或取消、下載構建產物。遠端寫入由明確操作觸發，不因刷新頁面自動執行。

<a id="reading"></a>
## 閱讀與翻譯

Markdown、相對路徑圖片、源碼、SVG 和媒體文件可直接預覽。文檔自動識別語言，使用獨立翻譯配置；譯文按原文、路徑和目標語言緩存，原文變化後不復用舊譯文。已是目標語言或文本不足時可保持原文。翻譯不是自動提交 README。

<a id="appearance"></a>
## 主題與界面

輕霧、輕毛玻璃、控制台、翠影、銀頁和曜幕共六種主題，區別包括佈局、面板、側欄和控件，不只是強調色。曜幕支持分開調整深淺色的背景、面板、文字、按鈕與狀態顏色，並提供珊瑚、海鹽、松霧、暮紫預設。

側欄分區可折疊、滾動，工作區域可調節尺寸。界面有 11 種語言，切換無需重啓；使用方法見應用內“幫助 → 使用指南”。

<a id="start"></a>
## 安裝與開始使用

從 [Releases](https://github.com/Lincb522/GitGatto/releases/latest) 下載 DMG，拖入“應用程序”。最低 macOS 14，發行包支持 Apple Silicon 與 Intel。正式版本和變更以 [更新日誌](CHANGELOG.md) 及 Release 為準，README 介紹當前倉庫能力。

| 使用範圍 | 前置條件 |
| --- | --- |
| 本地 Git 與普通遠程同步 | Git，以及相應遠程的 Git / SSH 認證 |
| GitHub 賬號、PR、Issue、Actions | 已登錄的 [GitHub CLI](https://cli.github.com/) |
| Agent、翻譯與 Agent 安裝 | 已設定的 CLI，或 OpenAI 相容 / DeepSeek API；模型與權限須支援所選任務 |
| Homebrew 工具檢測與升級 | Homebrew |

打開本地倉庫，或手動掃描後選擇添加；不會整盤自動導入。GitHub 登錄與 Agent 配置在設置中完成。應用更新從 GitHub Releases 和 Appcast 獲取。

<a id="data"></a>
## 數據與權限

倉庫列表、設置、目標、回歸記錄、對話、譯文、下載記錄和恢復點保存在本機；備份位置可更換。Git、SSH、GitHub CLI 和 Agent CLI 復用各自的憑據來源。

“本地保存”不等於“全部離線”：GitHub 功能會訪問 GitHub，Agent 與翻譯會將所需上下文交給配置的 CLI 或 API，後續數據處理取決於該工具及模型服務。執行前檢查待發送內容；不要在命令、草稿或故障膠囊里放入憑據。系統目錄變更仍受 macOS 授權約束。

<a id="docs"></a>
## 路線圖、架構與項目記錄

[路線圖與後續計劃](docs/ROADMAP.md) · [系統架構](docs/ARCHITECTURE.md) · [版本記錄](CHANGELOG.md)

![GitGatto 路線圖](docs/media/roadmap.svg)

![GitGatto 系統架構](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

路線圖依原始碼與版本紀錄更新，虛線為後續計畫。Star 圖更新於 2026-09-12 UTC，依目前 Stargazers 的加星日期累計，不含已取消的 Star；點擊查看線上紀錄。

<a id="development"></a>
## 從源碼運行

需要 macOS 14+、Swift 6.1+；Xcode 工程配置見 `project.yml`。

```sh
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test --no-parallel
swift run GitGatto
```

也可以打開 `GitGatto.xcodeproj` 使用 `GitGatto` scheme。修改工程結構後，用 XcodeGen 執行 `./scripts/generate-xcodeproj.sh` 重新生成，不手改工程文件。應用使用 SwiftUI、AppKit、WebKit、AVKit、Alamofire 和 Sparkle；版本由 `Package.resolved` 鎖定。

<a id="credits"></a>
## 貢獻與許可

貢獻約定見 [CONTRIBUTING.md](CONTRIBUTING.md)，安全問題見 [SECURITY.md](SECURITY.md)。感謝 [GitHub CLI](https://github.com/cli/cli)、[Sparkle](https://github.com/sparkle-project/Sparkle)、[Alamofire](https://github.com/Alamofire)、[Reicon](https://github.com/Lincb522/reicon) 及圖標、動畫資源作者；完整來源與許可見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

GitGatto 由 **ZIJIU522** 開發，基於 [MIT License](LICENSE) 開源。
