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
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon and Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://gatto.zijiu522.cn">Website</a>
  ·
  <a href="https://github.com/Lincb522/GitGatto/releases/latest">Download</a>
  ·
  <a href="CHANGELOG.md">Changelog</a>
  ·
  <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a>
</p>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/media/github-project.png" alt="GitHub project"><br><sub><b>GitHub project</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/workspace.png" alt="Working tree and diff"><br><sub><b>Working tree and diff</b></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="docs/media/recovery-center.png" alt="Recovery Center"><br><sub><b>Recovery Center</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/file-time-machine.png" alt="File Time Machine"><br><sub><b>File Time Machine</b></sub></td>
  </tr>
</table>

GitGatto is a native Git and GitHub client for macOS, supporting Apple Silicon and Intel. Alongside repository operations, it provides backups of uncommitted work, external Agent activity records, delivery goals, regression investigation, and development-tool setup.

<a id="why"></a>
## Why we built GitGatto

Writing the code is only part of the work. Untangling changes, finding the commit that introduced a regression, waiting for CI, reviewing a PR, and shipping a release all take time. Switching tasks can also leave drafts and uncommitted files behind.

Agents add practical questions: what changed, why, what evidence remains after a failure, and whether “done” actually means the result works. We built GitGatto to address those tasks, not just put buttons over Git commands. It uses system Git and existing CLIs while keeping changes, evidence, recovery points, and follow-up actions accessible.

[Recovery](#recovery) · [Menu-bar monitoring](#monitoring) · [Delivery goals](#goals) · [Commit grouping](#intent) · [Regression](#regression) · [Project tools](#project-tools) · [Installation](#install-tools)

<a id="features"></a>
## Distinctive features

<a id="recovery"></a>
### Back up uncommitted work and observe external changes

Recovery Center protects local repositories added to GitGatto. Scheduled, major-change, and manual backups skip unchanged content. Recovery points include a Git bundle and copies of uncommitted files, with at most three rotating points per repository.

- Create a recovery point before an in-app Agent writes. Repository Guard also observes deletion, lost uncommitted changes, ref rollback, and unavailable repositories affected by external Agents, terminals, or scripts.
- Inspect the reason and affected paths, then open the repository or recovery point. An alert is a request to investigate, not proof that a particular process caused damage.
- Staged writes and completion markers keep interrupted backups from being treated as valid recovery points after an abnormal exit.
- Inspect storage use, delete individual or repository backups, and migrate existing backups when changing directories. Restore creates a new copy rather than overwriting the source.

This is not a system-wide command interceptor. Unsaved files and files excluded by backup rules cannot be guaranteed recoverable.

<a id="monitoring"></a>
### Check repositories from the menu bar

Choose all repositories or one repository independently of the main window. Inspect uncommitted work, upstream status, recovery points, Actions, goals, and a year of daily activity dots.

Working-tree, remote, protection, Actions, and goal monitoring have separate switches in Settings, alongside the engine, menu-bar visibility, and refresh interval. Activity counts commits and observed changes, not working hours. Monitoring continues while the app runs in the background and stops when it quits.

<a id="goals"></a>
### Save delivery as a goal you can resume

Choose Deliver Current Changes, GitHub Delivery, Complete Release, or a natural-language goal. Review steps before creation; inspect progress, blockers, and records afterward. Search goals and filter active or historical work.

The selected flow checks staging, commits, push, PR, review, Actions, artifacts, Release, DMG, Appcast, and the installed version. Custom goals require approval of the Agent's proposed conditions. After interruption, GitGatto reads actual state again; Agent prose alone does not establish success. Merging, publishing tags, and installation retain separate confirmations.

<a id="intent"></a>
### Split mixed changes into commits

Change Center groups files or diff hunks with separate commit messages; an Agent can help organize the groups. Before execution, it checks missing or duplicate assignments and whether the repository changed, then creates a recovery point and commits in order.

Each commit runs a diff check or a chosen verification command. Failure triggers an attempt to restore the original HEAD and staging boundary. The recovery point remains available; automatic rollback is not guaranteed under every failure.

<a id="regression"></a>
### Investigate regressions in an isolated worktree

Run `git bisect` without switching your working directory. Automatic mode runs a verification command; manual mode marks candidates good, bad, or skipped. Commits, verdicts, exit codes, duration, and output stay with the investigation.

Pass the evidence to an Agent for a fix, verification, and PR preparation. The command must test the actual failure; too many skipped commits may leave more than one candidate.

<a id="evidence"></a>
### Code provenance, failure capsules, and activity records

- **Code Provenance:** trace a line to its commit, then inspect associated PRs, issues, reviews, and checks when GitHub CLI is available.
- **Reproduction Capsules:** export the base commit, patches, eligible untracked files, failing command, output, and tool versions as `.gatto`. Import validates structure and hashes before restoring an isolated worktree; embedded commands never run automatically. Only known sensitive paths and recognized content are filtered, so inspect before sharing.
- **External Agent activity:** associate file and ref changes with known Agent processes working in the repository and show evidence strength. A running process is not proof of responsibility for each change.

<a id="agent"></a>
### Agents beyond commit messages

Use Codex CLI, Claude Code, Gemini CLI, OpenCode, or a custom CLI. Built-in Git guidance covers staged review, commit drafting, conflicts, branch maintenance, history recovery, repository health, and release checks. Investigations can carry original Git LFS, hook, signing, or synchronization errors.

Project work, translation, search, and installation have separate execution lanes. Preview README rewrites before applying them. Issue and PR replies are drafted from discussion and diffs, remain editable, and are sent only after confirmation. Keep the CLI and model configuration you already use.

<a id="project-tools"></a>
### Save more than a branch when switching tasks

**Work scenes** save staged and unstaged changes, untracked files, the branch, drafts, selected file, and related goals and links. Restore checks repository state; a scene can also open in an isolated worktree. Ignored files are excluded, and a scene is not an independent backup.

| Tool | What it does |
| --- | --- |
| Code search | Search current files, a revision, or historical changes across managed repositories; filter directory, language, or extension, preview evidence, and send it to an Agent. Literal matching with bounded results. |
| Run commands | Discover project scripts or add custom commands, pin favorites, inspect live output, duration and exit status, stop, retry, and open local services. Noninteractive execution with JSON-array arguments. |
| Ignore rules | Explain rule sources; preview edits to shared `.gitignore` or local `.git/info/exclude`. Stop tracking without deleting disk files. |
| Commit identities | Bind author and signing settings by repository or directory, inspect effective sources, and check identity before committing. Git authorship is separate from GitHub sign-in. |

Open Project tools in the toolbar or use `⌘K`.

<a id="install-tools"></a>
### Finish configuration and verification after installation

The application catalog finds versions and assets from GitHub Releases and distinguishes downloads from installations. DMG and ZIP use the native installer; command-line packages go to an Agent. Download management shows stages, output, and retry actions.

The development catalog contains **99 tools and runtimes**, detects local versions, and supports multi-selection and batch upgrades. Installation and upgrade queues allow up to three concurrent tasks; Homebrew writes are serialized to avoid simultaneous dependency changes.

Tasks continue with required PATH setup, plugin registration, initialization, and configuration migration, then check the executable and actual version. A finished download or Agent message cannot replace local verification. Missing permissions or configuration remain actionable; account sign-in and system authorization still require you. The installed-app list records GitGatto installations, not every app on the Mac.

<a id="git-github"></a>
## Everyday Git and GitHub

- **Workspace and history:** stage, commit, diff, commit graph, blame, file history, and historical media; combine SHA, author, path, text, date, and ref search filters.
- **Branches and recovery:** branches, tags, remotes, stashes, worktrees, ref comparison, and recovery branches from reflog. Reorder, squash, split, amend, cherry-pick, revert, and reset; history rewriting checks published commits and destructive actions require confirmation.
- **Conflicts and diagnostics:** edit merge, rebase, or stash conflicts; continue, skip, or abort Git operations; inspect LFS, hooks, and tools.
- **Multi-repository sync:** batch fetch, pull, and push with separate ahead, behind, diverged, conflict, and failure results; retry failed items.
- **GitHub projects:** account repositories, repository/developer and natural-language search, Star, Fork, clone, code, README, Releases, and assets.
- **Inbox, issues, and PRs:** filter reviews, mentions, and failed checks; create and manage issues; review PR files, mark viewed, and post inline comments, replies, and reviews.
- **Actions:** inspect runs and logs, rerun or cancel, and download artifacts. Explicit actions trigger remote writes, not page refreshes.

<a id="reading"></a>
## Reading and translation

Preview Markdown, relative images, source, SVG, and media in the app. Documents use language detection and a separate translation configuration. Cached translations are keyed to source, path, and target language; changed source does not reuse stale text. Already-target-language or insufficient text can remain unchanged. Translation does not automatically commit a README.

<a id="appearance"></a>
## Themes and interface

Six themes—Light Mist, Soft Frosted Glass, Console, Emerald, Folio, Luminous Stage—vary layout, panels, sidebar, and controls, not only accents. Luminous Stage has separate light/dark background, panel, text, button, and status colors, with Coral, Coast, Forest, Dusk presets.

Sidebar sections collapse and scroll; workspace regions resize. Eleven interface languages switch without restarting. See Help → User Guide for instructions.

<a id="start"></a>
## Install and get started

Download the DMG from [Releases](https://github.com/Lincb522/GitGatto/releases/latest) and drag GitGatto into Applications. Requires macOS 14+; releases support Apple Silicon and Intel. [Changelog](CHANGELOG.md) and Releases identify shipped versions; this README describes the current repository.

| Use | Requirement |
| --- | --- |
| Local Git and ordinary remote sync | Git and the remote's Git / SSH authentication |
| GitHub account, PRs, issues, Actions | Signed-in [GitHub CLI](https://cli.github.com/) |
| Agents, translation, Agent installation | Installed CLI with its provider's required sign-in or configuration |
| Homebrew detection and upgrades | Homebrew |

Open a local repository or manually scan and select repositories to add; there is no automatic whole-disk import. Configure GitHub and Agents in Settings. Updates use GitHub Releases and the Appcast.

<a id="data"></a>
## Data and permissions

Repository lists, settings, goals, investigations, conversations, translations, download records, and recovery points are stored locally; backup storage can move. Git, SSH, GitHub CLI, and Agent CLIs reuse their credential sources.

Local storage does not mean everything is offline. GitHub features contact GitHub. Agents and translation pass necessary context to your configured CLI; subsequent handling depends on that tool and model service. Review what you send and keep credentials out of commands, drafts, and capsules. System-directory changes remain subject to macOS authorization.

<a id="docs"></a>
## Roadmap, architecture, and project history

[Roadmap and plans](docs/ROADMAP.md) · [Architecture](docs/ARCHITECTURE.md) · [Version history](CHANGELOG.md)

![GitGatto roadmap](docs/media/roadmap.svg)

![GitGatto architecture](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

The roadmap follows repository version records; dashed stages are plans. Star History is a committed data snapshot; follow the image link for the online record.

<a id="development"></a>
## Run from source

Requires macOS 14+ and Swift 6.1+. Xcode configuration lives in `project.yml`.

```sh
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
swift run GitGatto
```

Alternatively open `GitGatto.xcodeproj` with the `GitGatto` scheme. After structural changes, regenerate with XcodeGen via `./scripts/generate-xcodeproj.sh`; do not hand-edit the project. The app uses SwiftUI, AppKit, WebKit, AVKit, Alamofire, and Sparkle; versions are pinned in `Package.resolved`.

<a id="credits"></a>
## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Thanks to [GitHub CLI](https://github.com/cli/cli), [Sparkle](https://github.com/sparkle-project/Sparkle), [Alamofire](https://github.com/Alamofire), [Reicon](https://github.com/Lincb522/reicon), and the icon and animation authors. Full sources and licenses are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

GitGatto is developed by **ZIJIU522** and released under the [MIT License](LICENSE).
