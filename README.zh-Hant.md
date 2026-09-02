<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">原生建構，由 Agent 驅動的 Git 管理工具。</p>

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

GitGatto 是面向 macOS 的原生 Git 與 GitHub 用戶端。儲存庫狀態來自系統 Git，遠端操作使用 GitHub CLI，Agent 使用 Mac 上已安裝並登入的 CLI；應用程式把分散的狀態、步驟與結果放回同一個專案畫面。

## 為什麼開發 GitGatto

一次完整交付往往橫跨終端機、編輯器、GitHub、Actions 與發佈頁面。任何一步失敗，都要重新核對分支、暫存內容、執行記錄和建構產物。加入 Agent 後，還要確認它的工作目錄、權限以及上下文是否屬於目前儲存庫。

GitGatto 從這些日常問題開始：保留真實的 Git 與既有工具，把儲存庫操作、GitHub 協作、Agent 處理和失敗證據接成一條可以檢查、暫停與繼續的流程。

## 特色功能

### 專案目標

「交付目前修改」「GitHub 交付」和「完整發佈」會依照相依順序檢查暫存、提交、Push、Pull Request、Review、Actions、建構產物、Release、DMG、Appcast 與本機版本。也可以用自然語言描述結果，確認產生的條件後再執行。

每個步驟都讀取 Git、GitHub 或本機的實際狀態。中斷時保留已完成步驟；Actions 失敗可連同執行證據交給 Agent。合併、發佈標籤和安裝仍需分別確認。

### 回歸取證

在獨立 worktree 中執行 `git bisect`，不切換目前工作區。自動模式執行指定驗證命令，手動模式逐一標記正常、故障或略過；候選提交、結束碼、耗時和輸出會隨任務保存。找到第一個故障提交後，可以讓 Agent 修復、重新驗證並建立 Pull Request。

### 儲存庫災備

災備中心監控已加入 GitGatto 的本機儲存庫，按排程保存未提交程式碼，並在變更檔案數或行數達到門檻時立即建立還原點；也可隨時手動備份。沒有新變更或內容指紋相同時不會重複寫入。

備份包含儲存庫 Git bundle 與未提交檔案副本，每個儲存庫最多保留三份滾動還原點。可以查看空間占用、開啟備份目錄、刪除單份或整個儲存庫的備份，並將還原點還原成新的儲存庫副本。更換備份位置時，GitGatto 會遷移現有內容並核對結果。

### 面向 Git 的 Agent

支援 Codex CLI、Claude Code、Gemini CLI、OpenCode 與自訂 CLI。儲存庫操作、翻譯和軟體安裝使用獨立執行通道，長時間的儲存庫任務不會阻塞文件翻譯。

Agent 可以根據完整錯誤輸出處理 Git、Git LFS、Hook、簽署、分支、同步、衝突、Pull Request 和 Actions 問題；暫存區為空時可先暫存目前修改，再起草提交訊息，接著直接提交或提交並推送。README 重寫會先渲染完整結果，再由「提交套用」只提交該文件。

## Git 與 GitHub

- 管理工作區、暫存區、提交、Pull、Push、分支、貯藏和工作樹。
- 查看逐行 Diff、提交圖、Blame、單一檔案歷史，以及歷史版本中的圖片、SVG 和影片。
- 編輯合併、變基與貯藏衝突結果，再繼續、略過或中止操作。
- 從目前 GitHub 帳號載入可存取的儲存庫，搜尋儲存庫與開發者，支援模糊、自然語言和分頁載入。
- 在應用程式內查看程式碼、README、Pull Request、Actions、Releases 和發行附件。
- 審閱 Pull Request 檔案、標記已查看、發佈行評論、回覆與 Review；重新執行或取消 Actions，並下載建構產物。
- Star、Fork、複製儲存庫；本機掃描由使用者手動啟動並選擇要加入的項目，不會整碟匯入。

## 文件、翻譯與內容預覽

- 在 GitGatto 內渲染儲存庫 Markdown、相對路徑圖片和內部連結。
- 自動辨識文件語言，透過獨立 Agent 通道翻譯；譯文按原文版本保存在本機，可直接切換。
- 從工作區、提交歷史與檔案歷史預覽原始碼、圖片、SVG 原始碼和媒體檔案。
- README Agent 依據儲存庫檔案、相依套件和既有素材重組文件，不只修改措辭。

## 應用程式倉庫與開發工具

- 從 GitHub Releases 檢索可安裝應用程式，讀取實際圖示、介紹、螢幕截圖、版本和安裝包；DMG 與 ZIP 使用本機安裝流程，其他格式交給 Agent。
- 開發工具中心收錄 99 種執行環境、建構工具、容器、雲端工具、資料庫和命令列工具，並檢查本機版本與可用更新。
- 安裝與升級支援三路並行佇列、多選和批次升級；Homebrew 變更使用獨立序列佇列，避免同時寫入 Cellar。
- 安裝後由 Agent 完成目前使用者需要的 PATH、元件註冊、初始化與設定遷移，再重新檢查執行檔和版本。
- 下載、安裝、設定和驗證會保留階段進度、原始輸出和已知錯誤的本地化說明。

## 專案文件

- [路線圖](docs/ROADMAP.md)：已實現階段、後續計畫與邊界。
- [架構圖](docs/ARCHITECTURE.md)：狀態所有權、服務邊界和主要資料流。
- [更新曲線](docs/UPDATE_HISTORY.md)：依 CHANGELOG 實際日期產生的版本記錄。

![GitGatto roadmap](docs/media/roadmap.svg)

![GitGatto architecture](docs/media/architecture-overview.svg)

![GitGatto 更新曲線](docs/media/update-curve.svg)

## 安裝

從 [Releases](https://github.com/Lincb522/GitGatto/releases/latest) 下載 DMG，將 GitGatto 拖入「應用程式」。發行包同時支援 Apple Silicon 與 Intel，最低系統版本為 macOS 14。

| 功能 | 需要 |
| --- | --- |
| 本機儲存庫 | Git |
| GitHub 儲存庫、PR、Actions 與遠端操作 | 已登入的 [GitHub CLI](https://cli.github.com/) |
| Agent | 至少一個已安裝並登入的支援 CLI |
| Homebrew 更新檢查 | Homebrew |

應用程式內更新、版本記錄和安裝包均來自本儲存庫的 GitHub Releases。

## 本機資料與權限

- 設定、儲存庫清單、專案目標、回歸取證記錄、Agent 對話與操作記錄、下載記錄和譯文保存在本機。
- 開啟災備後，Git bundle 與未提交檔案副本保存在應用程式支援目錄或你選擇的位置；每個儲存庫最多保留三份，可在災備中心刪除。
- Git、SSH、GitHub CLI 與 Agent CLI 繼續使用各自的憑證來源；GitGatto 不保存 Token、密碼或私密金鑰。
- Pull、Push、Fork、評論、Review、Actions 操作、應用程式安裝和開發工具變更都由明確的應用程式操作觸發。

## 開發

需要 macOS 14 或更新版本，以及專案宣告的 Swift 工具鏈。

```bash
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
open GitGatto.xcodeproj
```

程式碼使用 Swift 6、SwiftUI、AppKit、WebKit 與 AVKit；網路和更新分別使用 Alamofire 5.12 與 Sparkle 2.9.6。貢獻規則見 [CONTRIBUTING.md](CONTRIBUTING.md)，架構邊界見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 致謝

- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Alamofire](https://github.com/Alamofire/Alamofire)
- [SwiftUI-Animations](https://github.com/Shubham0812/SwiftUI-Animations)
- [GitHub CLI](https://github.com/cli/cli)
- [Simple Icons](https://github.com/simple-icons/simple-icons)、[VSCode Icons](https://github.com/vscode-icons/vscode-icons)、[Devicon](https://github.com/devicons/devicon) 與 [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)

實際版本與授權見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。安全問題請依照 [SECURITY.md](SECURITY.md) 的管道回報。

## 授權

GitGatto 由 **ZIJIU522** 開發，依 [MIT License](LICENSE) 開源。
