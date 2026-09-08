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
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="最新リリース" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon と Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://gatto.zijiu522.cn">Web サイト</a>
  ·
  <a href="https://github.com/Lincb522/GitGatto/releases/latest">ダウンロード</a>
  ·
  <a href="CHANGELOG.md">変更履歴</a>
  ·
  <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a>
</p>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/media/github-project.png" alt="GitHub プロジェクト"><br><sub><b>GitHub プロジェクト</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/workspace.png" alt="ワークツリーと Diff"><br><sub><b>ワークツリーと Diff</b></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="docs/media/recovery-center.png" alt="リカバリーセンター"><br><sub><b>リカバリーセンター</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/file-time-machine.png" alt="ファイルタイムマシン"><br><sub><b>ファイルタイムマシン</b></sub></td>
  </tr>
</table>

GitGatto は Apple Silicon と Intel に対応する macOS ネイティブの Git / GitHub クライアントです。日常の操作に加え、未コミットのコードのバックアップ、外部 Agent の活動記録、目標に沿ったリリース作業、回帰調査、開発ツールのセットアップを扱います。

<a id="why"></a>
## GitGatto を作った理由

コードを書いた後にも、混在する変更の整理、回帰を起こしたコミットの特定、CI の確認、PR レビュー、リリースが残ります。途中で別の作業に移ると、下書きや未コミットのファイルを見失うこともあります。

Agent を使うと「何を、なぜ変えたか」「失敗の証拠はどこか」「完了と言っているが動くのか」も確認が必要です。GitGatto は Git にボタンを付けるだけでなく、この確認と復旧を扱うために作りました。システムの Git と既存の CLI を使い、変更、証拠、復元ポイント、次の操作を確認できます。

[復旧](#recovery) · [監視](#monitoring) · [目標](#goals) · [変更の整理](#intent) · [回帰調査](#regression) · [プロジェクトツール](#project-tools) · [インストール](#install-tools)

<a id="features"></a>
## 主な特徴

<a id="recovery"></a>
### 未コミットのコードと外部 Agent による変更を保護

登録したローカルリポジトリを、定期、大規模変更時、手動でバックアップします。同じ内容は重複保存しません。Git bundle と未コミットのファイルを含む復元ポイントを、リポジトリごとに最大三世代保持します。

アプリ内 Agent の書き込み前に復元ポイントを作成できます。外部 Agent、ターミナル、スクリプトによる削除、未コミット内容の消失、参照の巻き戻り、リポジトリの利用不能も監視し、理由と影響パスを表示します。警告だけで原因のプロセスを断定しません。

段階的な書き込みと完了マーカーにより、異常終了時の未完成コピーを有効なバックアップと区別します。使用量の確認、個別・リポジトリ単位の削除、保存先変更時の移行に対応。復元は別のディレクトリへ行い、元のリポジトリを上書きしません。システム全体のコマンドを遮断する機能ではなく、未保存・除外ファイルの復旧は保証できません。

<a id="monitoring"></a>
### メニューバーから全リポジトリを確認

メインウインドウとは独立して全体または一つを選び、変更、上流との同期、復元ポイント、Actions、目標、過去一年の日別活動を確認できます。

作業ツリー、リモート、保護、Actions、目標の各監視と、全体・メニューバーの表示・更新間隔は設定で調整します。点の数はコミットと観測した変更であり、作業時間ではありません。アプリがバックグラウンドで動作中は監視を続け、終了すると停止します。

<a id="goals"></a>
### 中断後も続けられる目標

現在の変更の納品、GitHub での納品、完全なリリース、自然言語によるカスタム目標を選べます。作成前に手順を確認し、実行後は進捗、停止理由、記録を表示。検索と進行中・履歴の絞り込みも可能です。

選択した流れに応じてステージ、コミット、Push、PR、Review、Actions、成果物、Release、DMG、Appcast、本機のバージョンを確認します。カスタム条件は Agent の提案を承認してから実行。中断後は実際の状態を再取得します。Agent の文章を成功の根拠にはせず、マージ、タグ公開、インストールには個別の確認があります。

<a id="intent"></a>
### 混在する変更をコミットに分ける

ファイルや Diff の hunk ごとにグループとコミットメッセージを設定し、Agent に整理を依頼できます。漏れ・重複とリポジトリの変化を確認し、復元ポイントを作成して順番にコミットします。

各コミットに差分チェックまたは指定した検証コマンドを実行します。失敗時は元の HEAD とステージ境界への復帰を試みますが、常に成功する保証はありません。必要なら復元ポイントを確認できます。

<a id="regression"></a>
### 独立した worktree で回帰を調査

作業中のディレクトリを切り替えずに `git bisect` を実行します。自動モードは検証コマンド、手動モードは正常・不具合・スキップで判定。候補、判定、終了コード、時間、出力を保存します。

特定した証拠を Agent に渡して修正、再検証、PR の準備に進めます。コマンドが対象の問題を判定できる必要があり、スキップが多いと候補が一つに絞れない場合があります。

<a id="evidence"></a>
### コードの由来・障害カプセル・活動記録

- **コードの由来**：行からコミットへ遡り、GitHub CLI が使える場合は関連 PR、Issue、Review、Checks を確認します。
- **障害カプセル**：基準コミット、パッチ、収録可能な未追跡ファイル、失敗コマンド、出力、ツールのバージョンを `.gatto` に書き出します。構造とハッシュを検証して独立 worktree に復元し、収録コマンドは自動実行しません。除外・伏字処理は既知の内容だけなので共有前の確認が必要です。
- **外部 Agent の活動**：ファイルと参照の変化を、リポジトリ内で作業していた既知の Agent プロセスと関連付け、証拠の強さを表示します。起動していた事実だけでは変更の責任を断定できません。

<a id="agent"></a>
### コミット文の作成だけではない Agent

Codex CLI、Claude Code、Gemini CLI、OpenCode、カスタム CLI に対応。内蔵の Git 指針はステージのレビュー、コミット案、競合、分岐の整理、履歴復旧、健全性、リリース確認を扱い、LFS、hooks、署名、同期のエラー出力も調査に渡せます。

プロジェクト、翻訳、検索、インストールは別の実行経路です。README は書き換え結果をプレビューして適用。Issue・PR 返信は議論と差分から編集可能な下書きを作り、確認後に送信します。利用中の CLI とモデル設定を引き継げます。

<a id="project-tools"></a>
### ブランチ以外の作業状態も保存

**作業状態**はステージ済み・未ステージ・未追跡ファイル、ブランチ、下書き、選択ファイル、関連目標・リンクを保存します。復元時に状態を確認し、独立 worktree でも開けます。無視ファイルは対象外で、独立したバックアップではありません。

| ツール | 内容 |
| --- | --- |
| コード検索 | 管理中のリポジトリの現在、指定リビジョン、履歴変更を横断検索。ディレクトリ、言語、拡張子で絞り、証拠を Agent に渡せます。正規表現ではなく通常文字列の検索で、結果数に上限があります。 |
| コマンド実行 | プロジェクトスクリプトを検出、自作コマンドを登録・固定。出力、所要時間、終了状態、停止、再実行、ローカルサービスを開く操作に対応。非対話式で、引数は JSON 配列です。 |
| 除外ルール | 出所を確認し、プレビュー後に共有 `.gitignore` またはローカル `.git/info/exclude` を編集。追跡解除してもディスクのファイルは残します。 |
| コミットのユーザー情報 | リポジトリ・ディレクトリごとに作者と署名を設定し、有効な値の出所とコミット前の整合性を確認。GitHub ログインとは別です。 |

ツールバーのプロジェクトツール、または `⌘K` から開きます。

<a id="install-tools"></a>
### インストール後の設定と確認まで

GitHub Releases のバージョンと添付を探し、ダウンロードとインストールを区別します。DMG・ZIP はネイティブ処理、コマンドライン形式は Agent へ。管理画面で段階、出力、再試行を確認できます。

**99 種の開発ツールとランタイム**の本機バージョンを検出し、複数選択・一括更新に対応。インストールと更新のキューは最大三並列、Homebrew の書き込みは直列化します。

必要な PATH、プラグイン登録、初期化、設定移行を行ってから実行ファイルとバージョンを確認します。ダウンロード完了や Agent の報告だけでは成功になりません。残る権限・設定を表示し、ログインとシステム認可は本人が行います。インストール済み一覧は GitGatto の記録で、Mac 全体のアプリ一覧ではありません。

<a id="git-github"></a>
## 日常の Git / GitHub 操作

- ステージ、コミット、Diff、コミットグラフ、Blame、ファイル履歴、過去のメディア。SHA・作者・パス・本文・日付・参照で複合検索。
- 分岐、タグ、リモート、stash、worktree、参照比較、reflog からの復旧分岐。並べ替え、squash、分割、修正、cherry-pick、revert、reset。履歴書換え前に公開済みコミットを確認し、破壊的操作は確認を求めます。
- merge・rebase・stash の競合編集と継続・スキップ・中止、LFS・hooks・ツール診断。
- 複数リポジトリの fetch・pull・push。先行、遅延、分岐、競合、失敗を個別表示し失敗分を再試行。
- アカウントのリポジトリ、開発者・自然言語検索、Star、Fork、clone、コード、README、Release と添付。
- 受信箱でレビュー・メンション・失敗チェックを整理。Issue の作成・管理、PR ファイルの確認済みマーク、行コメント、返信、Review。
- Actions の実行・ログ確認、再実行・中止、成果物取得。画面更新はリモート書き込みを起動しません。

<a id="reading"></a>
## 閲覧と翻訳

Markdown、相対画像、ソース、SVG、メディアをアプリ内で表示します。言語を検出し、独立設定で翻訳。原文・パス・対象言語に対応するキャッシュを使い、原文変更時は古い訳を流用しません。対象言語と同じ、または短すぎる文章は原文のままになる場合があります。README を自動コミットする機能ではありません。

<a id="appearance"></a>
## テーマと画面

ライトミスト、ソフトすりガラス、コンソール、エメラルド、フォリオ、光幕 の六テーマはレイアウト、パネル、サイドバー、操作部品も異なります。光幕 は明暗別に背景・パネル・文字・ボタン・状態色を設定でき、コーラル、海岸、森林、夕暮れ を用意しています。

サイドバーは折りたたみ・スクロール、作業領域はサイズ調整に対応。11 言語を再起動なしで切り替えられます。操作はアプリ内のヘルプに記載しています。

<a id="start"></a>
## インストールと開始

[Releases](https://github.com/Lincb522/GitGatto/releases/latest) の DMG を開き、アプリケーションへ移動します。macOS 14+、Apple Silicon / Intel 対応。公開版は [変更履歴](CHANGELOG.md) と Release、本書は現在のリポジトリを説明します。

| 用途 | 必要なもの |
| --- | --- |
| ローカル Git・通常の同期 | Git と接続先の Git / SSH 認証 |
| GitHub・PR・Issue・Actions | ログイン済み [GitHub CLI](https://cli.github.com/) |
| Agent・翻訳・Agent インストール | 対応 CLI と提供元が求めるログイン・設定 |
| Homebrew の検出・更新 | Homebrew |

リポジトリを開くか、手動スキャンから選んで追加します。全ディスクの自動登録はしません。GitHub・Agent は設定画面で構成し、アプリ更新は GitHub Releases と Appcast を利用します。

<a id="data"></a>
## データと権限

設定、リポジトリ一覧、目標、調査、会話、訳文、ダウンロード記録、復元ポイントは本機に保存します。バックアップ先は移行可能。認証は Git、SSH、GitHub CLI、Agent CLI の既存の保存先を使います。

ローカル保存は完全オフラインを意味しません。GitHub へ通信し、Agent・翻訳に必要な文脈を設定した CLI へ渡します。その後の扱いはツールとモデルサービスに依存します。送信内容を確認し、コマンド・下書き・カプセルに認証情報を入れないでください。システムディレクトリの変更には macOS の認可が必要です。

<a id="docs"></a>
## 計画・構成・開発記録

[ロードマップ](docs/ROADMAP.md) · [アーキテクチャ](docs/ARCHITECTURE.md) · [変更履歴](CHANGELOG.md)

![GitGatto ロードマップ](docs/media/roadmap.svg)

![GitGatto 構成](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

ロードマップはバージョン記録に基づき、破線は計画です。Star History は保存済みスナップショットで、オンライン記録は画像リンクから確認できます。

<a id="development"></a>
## ソースから実行

macOS 14+、Swift 6.1+ が必要です。Xcode 設定は `project.yml` にあります。

```sh
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
swift run GitGatto
```

`GitGatto.xcodeproj` の `GitGatto` scheme でも実行できます。構造変更後は XcodeGen を使い `./scripts/generate-xcodeproj.sh` で再生成します。工程ファイルを直接編集しません。SwiftUI、AppKit、WebKit、AVKit、Alamofire、Sparkle を使用し、依存版は `Package.resolved` に固定しています。

<a id="credits"></a>
## 貢献とライセンス

[貢献方法](CONTRIBUTING.md)・[セキュリティ](SECURITY.md)をご覧ください。[GitHub CLI](https://github.com/cli/cli)、[Sparkle](https://github.com/sparkle-project/Sparkle)、[Alamofire](https://github.com/Alamofire)、[Reicon](https://github.com/Lincb522/reicon) と画像・アニメーション作者に感謝します。全出典は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

**ZIJIU522** が開発し、[MIT License](LICENSE) で公開しています。
