<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">A native, Agent-driven Git client.</p>

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
    <td width="50%" align="center"><img src="docs/media/file-history-dark.png" alt="File history in dark mode"><br><sub><b>File history in dark mode</b></sub></td>
  </tr>
</table>

GitGatto is a native Git and GitHub client for macOS. Repository state comes from the system Git, remote operations use GitHub CLI, and Agents use CLI tools already installed and signed in on the Mac. GitGatto brings their state, steps, and results into one project view.

## Why GitGatto exists

A complete delivery often spans a terminal, editor, GitHub, Actions, and a release page. When one step fails, the branch, staged files, run logs, and artifacts must all be checked again. Adding an Agent also raises practical questions about its working directory, permissions, and whether its context belongs to the current repository.

GitGatto started with those everyday problems. It keeps the real Git and existing tools, then connects repository operations, GitHub collaboration, Agent work, and failure evidence into a process that can be inspected, paused, and resumed.

## Distinctive workflows

### Project Goals

“Deliver Current Changes,” “GitHub Delivery,” and “Complete Release” check staged changes, commits, pushes, pull requests, reviews, Actions, artifacts, Releases, DMGs, the Appcast, and the installed app version in dependency order. A goal can also be described in natural language and its generated conditions reviewed before execution.

Every step reads actual Git, GitHub, or local state. Completed steps survive interruptions, and a failed Actions run can be passed to an Agent with its evidence. Merging, publishing a tag, and installing a release still require separate confirmation.

### Regression Investigation

Runs `git bisect` in an isolated worktree without switching the current workspace. Automatic mode executes a chosen verification command; manual mode marks each candidate as good, bad, or skipped. Candidate commits, exit codes, elapsed time, and output are saved with the investigation. Once the first bad commit is found, the Agent can prepare a fix, rerun verification, and open a pull request.

### Repository Recovery

The Recovery Center monitors local repositories added to GitGatto. It saves uncommitted work on a schedule, creates a recovery point when file or line thresholds are reached, and also supports manual backups. Unchanged content is not written again.

A recovery point contains a repository Git bundle and copies of uncommitted files. Each repository keeps at most three rolling points. You can inspect storage usage, reveal backup folders, delete one point or a repository's full history, and restore a point as a new repository copy. Changing the backup location migrates existing data and verifies the result before switching.

### Git-focused Agents

GitGatto supports Codex CLI, Claude Code, Gemini CLI, OpenCode, and custom CLI templates. Repository work, translation, and software installation use separate execution channels, so a long repository task does not block document translation.

An Agent can use complete error output to handle Git, Git LFS, hooks, signing, branches, synchronization, conflicts, pull requests, and Actions failures. If nothing is staged, commit drafting can stage the current changes first, then commit or commit and push. A README rewrite is rendered in full before “Apply Commit” commits only that document.

## Git and GitHub

- Manage working-tree changes, staging, commits, pull, push, branches, stashes, and worktrees.
- Inspect line diffs, the commit graph, blame, per-file history, and images, SVGs, or video from historical revisions.
- Edit merge, rebase, and stash-conflict results, then continue, skip, or abort the operation.
- Load repositories available to the current GitHub account; search repositories and developers with fuzzy, natural-language, and paginated results.
- Read code, READMEs, pull requests, Actions, Releases, and release assets without leaving the app.
- Review pull-request files, mark files viewed, add line comments, reply, submit reviews, rerun or cancel Actions, and download artifacts.
- Star, fork, and clone repositories. Local repository scanning is manual and lets you choose what to add instead of importing an entire disk.

## Documents, translation, and previews

- Render repository Markdown, relative images, and internal links inside GitGatto.
- Detect the document language and translate through a separate Agent channel. Translations are cached by source version and can be switched without running again.
- Preview source code, images, SVG source, and media files from the workspace, commit history, and file history.
- The README Agent rebuilds a document from repository files, dependencies, and existing assets instead of making a wording-only edit.

## App Catalog and developer tools

- Find installable applications from GitHub Releases with their actual icon, description, screenshots, version, and packages. DMG and ZIP packages use the local installer; other formats are handled by an Agent.
- Detect installed versions and available updates for a catalog of 99 runtimes, build tools, container tools, cloud tools, databases, and command-line utilities.
- Run installs and upgrades through a three-lane queue with multi-select and batch upgrades. Homebrew mutations use a separate serial queue to avoid simultaneous writes to the Cellar.
- After installation, the Agent completes required per-user PATH changes, component registration, initialization, and configuration migration, then verifies the executable and version again.
- Download, installation, configuration, and verification retain stage progress, original output, and localized explanations for known errors.

## Project documents

- [Roadmap](docs/ROADMAP.md): implemented stages, planned work, and boundaries.
- [Architecture](docs/ARCHITECTURE.md): state ownership, service boundaries, and key data flows.
- [Release activity](docs/UPDATE_HISTORY.md): version history generated from dated CHANGELOG entries.

![GitGatto roadmap](docs/media/roadmap.svg)

![GitGatto architecture](docs/media/architecture-overview.svg)

![GitGatto release activity](docs/media/update-curve.svg)

## Installation

Download the DMG from [Releases](https://github.com/Lincb522/GitGatto/releases/latest) and drag GitGatto into Applications. Releases are universal binaries for Apple Silicon and Intel and require macOS 14 or later.

| Capability | Requirement |
| --- | --- |
| Local repositories | Git |
| GitHub repositories, PRs, Actions, and remote operations | Signed-in [GitHub CLI](https://cli.github.com/) |
| Agent workflows | At least one installed and signed-in supported CLI |
| Homebrew update checks | Homebrew |

In-app updates, release notes, and installers all come from this repository's GitHub Releases.

## Local data and permissions

- Settings, repository lists, Project Goals, Regression Investigations, Agent conversations and operation logs, downloads, and translations remain on the Mac.
- When repository protection is enabled, Git bundles and copies of uncommitted files are stored in Application Support or a location you choose. Each repository keeps no more than three copies, which can be removed from the Recovery Center.
- Git, SSH, GitHub CLI, and Agent CLIs keep using their own credential stores. GitGatto does not store tokens, passwords, or private keys.
- Pull, push, fork, comment, review, Actions, application installation, and developer-tool changes run only after an explicit action in the app.

## Development

Development requires macOS 14 or later and the Swift toolchain declared by the project.

```bash
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
open GitGatto.xcodeproj
```

The codebase uses Swift 6, SwiftUI, AppKit, WebKit, and AVKit. Networking uses Alamofire 5.12 and updates use Sparkle 2.9.6. See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution rules and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for system boundaries.

## Acknowledgments

- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Alamofire](https://github.com/Alamofire/Alamofire)
- [SwiftUI-Animations](https://github.com/Shubham0812/SwiftUI-Animations)
- [GitHub CLI](https://github.com/cli/cli)
- [Simple Icons](https://github.com/simple-icons/simple-icons), [VSCode Icons](https://github.com/vscode-icons/vscode-icons), [Devicon](https://github.com/devicons/devicon), and [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)

Exact versions and licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Report security issues through the channel in [SECURITY.md](SECURITY.md).

## License

GitGatto is developed by **ZIJIU522** and released under the [MIT License](LICENSE).
