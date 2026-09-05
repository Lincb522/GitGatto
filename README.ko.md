<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">macOS 네이티브로 만든 Agent 기반 Git 클라이언트.</p>

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
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="최신 릴리스" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon 및 Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://gatto.zijiu522.cn">웹사이트</a>
  ·
  <a href="https://github.com/Lincb522/GitGatto/releases/latest">다운로드</a>
  ·
  <a href="CHANGELOG.md">변경 기록</a>
  ·
  <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a>
</p>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/media/github-project.png" alt="GitHub 프로젝트"><br><sub><b>GitHub 프로젝트</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/workspace.png" alt="작업 트리와 Diff"><br><sub><b>작업 트리와 Diff</b></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="docs/media/recovery-center.png" alt="재해 복구 센터"><br><sub><b>재해 복구 센터</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/file-time-machine.png" alt="파일 타임머신"><br><sub><b>파일 타임머신</b></sub></td>
  </tr>
</table>

GitGatto는 macOS용 네이티브 Git 및 GitHub 클라이언트입니다. 저장소 상태는 시스템 Git에서 읽고, 원격 작업은 GitHub CLI를 사용하며, Agent는 Mac에 이미 설치되고 로그인된 CLI를 사용합니다. 각 도구의 상태, 단계, 결과를 하나의 프로젝트 화면에 모읍니다.

## GitGatto를 만든 이유

한 번의 배포도 터미널, 편집기, GitHub, Actions, 릴리스 페이지를 오가며 진행됩니다. 중간 단계가 실패하면 브랜치, 스테이징 파일, 실행 로그, 빌드 산출물을 다시 확인해야 합니다. Agent까지 사용하면 작업 디렉터리, 권한, 현재 저장소에 맞는 컨텍스트인지도 확인해야 합니다.

GitGatto는 이런 일상적인 문제에서 시작했습니다. 실제 Git과 기존 도구는 그대로 두고, 저장소 작업, GitHub 협업, Agent 처리, 실패 증거를 확인하고 멈췄다가 이어갈 수 있는 흐름으로 연결합니다.

## 주요 워크플로

### 프로젝트 목표

‘현재 변경 배포’, ‘GitHub 배포’, ‘전체 릴리스’는 스테이징, 커밋, Push, Pull Request, Review, Actions, 빌드 산출물, Release, DMG, Appcast, 설치된 앱 버전을 의존 순서대로 확인합니다. 자연어로 원하는 결과를 적고 생성된 조건을 검토한 뒤 실행할 수도 있습니다.

각 단계는 Git, GitHub 또는 로컬의 실제 상태를 읽습니다. 작업이 중단되어도 완료된 단계는 남으며, 실패한 Actions 실행은 관련 증거와 함께 Agent에 전달할 수 있습니다. 병합, 태그 공개, 설치는 각각 별도의 확인이 필요합니다.

### 변경 구성 및 증거

- 변경 센터는 파일 또는 Diff 헝크별로 변경 의도를 정리하고 여러 원자적 커밋으로 나눌 수 있습니다. 실행 전에 저장소 지문을 확인하고 복구 지점을 만들며, 커밋이나 검증이 실패하면 기존 HEAD와 스테이징 경계를 복원합니다.
- 코드 출처는 파일의 한 줄에서 커밋을 추적하고, GitHub CLI를 사용할 수 있으면 관련 Pull Request, Issue, Review, Checks를 함께 표시합니다.
- 재현 캡슐은 패치, 추적되지 않은 파일, 기준 커밋, 실패 명령, 출력, 도구 버전을 `.gatto`로 묶습니다. 가져올 때 내용을 검증하고 독립 worktree에 복원합니다.
- 활동 원장은 Git 참조와 파일 상태 변화, 당시 작업 디렉터리가 저장소 안에 있던 Agent 프로세스를 기록합니다. 연관 신뢰도를 따로 표시하며 상관관계를 확정된 책임으로 표현하지 않습니다.

### 회귀 조사

현재 작업 공간을 바꾸지 않고 독립 worktree에서 `git bisect`를 실행합니다. 자동 모드는 지정한 검증 명령을 실행하고, 수동 모드는 각 후보를 정상, 문제, 건너뛰기로 판정합니다. 후보 커밋, 종료 코드, 소요 시간, 출력은 조사 기록에 저장됩니다. 첫 문제 커밋을 찾은 뒤 Agent로 수정하고 다시 검증한 다음 Pull Request를 만들 수 있습니다.

### 저장소 재해 복구

복구 센터는 GitGatto에 추가된 로컬 저장소를 감시합니다. 커밋하지 않은 작업을 일정에 따라 저장하고, 변경 파일 수나 줄 수가 기준에 도달하면 즉시 복구 지점을 만듭니다. 수동 백업도 지원하며 내용이 같으면 다시 쓰지 않습니다.

복구 지점에는 저장소 Git bundle과 커밋하지 않은 파일의 사본이 포함됩니다. 저장소마다 최대 3개의 순환 복구 지점을 유지합니다. 사용 공간 확인, 백업 폴더 열기, 단일 또는 저장소 전체 백업 삭제, 새 저장소 사본으로 복원이 가능합니다. 백업 위치를 변경하면 기존 데이터를 이전하고 검증한 뒤 새 위치로 전환합니다.

### Git 작업에 맞춘 Agent

Codex CLI, Claude Code, Gemini CLI, OpenCode 및 사용자 지정 CLI를 지원합니다. 저장소 작업, 번역, 소프트웨어 설치가 별도의 실행 채널을 사용하므로 긴 저장소 작업 중에도 문서 번역을 실행할 수 있습니다.

Agent는 전체 오류 출력을 바탕으로 Git, Git LFS, Hook, 서명, 브랜치, 동기화, 충돌, Pull Request, Actions 문제를 처리할 수 있습니다. 스테이징 영역이 비어 있으면 현재 변경을 먼저 스테이징한 뒤 커밋 메시지를 작성하고, 바로 커밋하거나 커밋 후 Push할 수 있습니다. README 재작성 결과는 먼저 완전히 렌더링되며, ‘커밋 적용’은 해당 문서만 커밋합니다.

## Git 및 GitHub

- 작업 트리, 스테이징, 커밋, Pull, Push, 브랜치, Stash, worktree 관리.
- 줄 단위 Diff, 커밋 그래프, Blame, 파일별 기록, 과거 리비전의 이미지·SVG·동영상 확인.
- 병합, rebase, Stash 충돌 결과를 편집한 뒤 계속, 건너뛰기 또는 중단.
- 현재 GitHub 계정이 접근할 수 있는 저장소를 불러오고 저장소와 개발자를 퍼지 검색, 자연어 검색, 추가 로딩.
- 코드, README, Pull Request, Actions, Releases, 릴리스 첨부 파일을 앱 안에서 확인.
- Pull Request 파일 검토, 확인 표시, 줄 댓글, 답글, Review 제출, Actions 재실행·취소, 산출물 다운로드.
- Star, Fork, Clone 지원. 로컬 검색은 수동으로 시작하며 디스크 전체를 가져오지 않고 추가할 저장소를 선택합니다.

## 문서, 번역 및 미리보기

- 저장소 Markdown, 상대 경로 이미지, 내부 링크를 GitGatto 안에서 렌더링.
- 문서 언어를 자동 판별하고 별도 Agent 채널로 번역. 번역본은 원문 버전별로 로컬에 저장되어 다시 실행하지 않고 전환 가능.
- 작업 공간, 커밋 기록, 파일 기록에서 소스 코드, 이미지, SVG 소스, 미디어 파일 미리보기.
- README Agent는 문구만 바꾸지 않고 저장소 파일, 의존성, 기존 자산을 바탕으로 문서 구성을 다시 만듭니다.

## 앱 카탈로그 및 개발 도구

- GitHub Releases에서 설치 가능한 앱을 검색하고 실제 아이콘, 설명, 스크린샷, 버전, 패키지를 표시. DMG와 ZIP은 로컬 설치 절차를 사용하고 다른 형식은 Agent가 처리.
- 런타임, 빌드 도구, 컨테이너, 클라우드 도구, 데이터베이스, CLI 99종의 설치 버전과 업데이트 확인.
- 3개 실행 레인에서 설치와 업그레이드를 병렬 처리하고 다중 선택 및 일괄 업그레이드 지원. Homebrew 변경은 별도 직렬 큐를 사용해 Cellar 동시 쓰기를 방지.
- 설치 후 Agent가 사용자별 PATH, 구성 요소 등록, 초기화, 설정 이전을 완료하고 실행 파일과 버전을 다시 확인.
- 다운로드, 설치, 설정, 검증의 단계별 진행 상황과 원본 출력, 알려진 오류의 현지화된 설명 보존.

## 프로젝트 문서

- [로드맵](docs/ROADMAP.md): 구현 완료 단계, 다음 계획 및 범위.
- [아키텍처](docs/ARCHITECTURE.md): 상태 소유권, 서비스 경계 및 주요 데이터 흐름.
- [Star History](https://www.star-history.com/#Lincb522/GitGatto&Date): GitHub Star 증가 기록.

![GitGatto roadmap](docs/media/roadmap.svg)

![GitGatto architecture](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

## 설치

[Releases](https://github.com/Lincb522/GitGatto/releases/latest)에서 DMG를 내려받아 GitGatto를 응용 프로그램 폴더로 드래그합니다. 배포본은 Apple Silicon과 Intel을 모두 지원하며 macOS 14 이상이 필요합니다.

| 기능 | 필요 항목 |
| --- | --- |
| 로컬 저장소 | Git |
| GitHub 저장소, PR, Actions 및 원격 작업 | 로그인된 [GitHub CLI](https://cli.github.com/) |
| Agent 워크플로 | 설치되고 로그인된 지원 CLI 한 개 이상 |
| Homebrew 업데이트 확인 | Homebrew |

앱 내 업데이트, 릴리스 노트, 설치 파일은 모두 이 저장소의 GitHub Releases에서 가져옵니다.

## 로컬 데이터 및 권한

- 설정, 저장소 목록, 프로젝트 목표, 회귀 조사 기록, Agent 대화와 작업 기록, 다운로드, 번역은 Mac에 저장됩니다.
- 저장소 보호를 켜면 Git bundle과 커밋하지 않은 파일 사본이 Application Support 또는 선택한 위치에 저장됩니다. 저장소마다 최대 3개를 유지하며 복구 센터에서 삭제할 수 있습니다.
- Git, SSH, GitHub CLI, Agent CLI는 각자의 자격 증명 저장소를 계속 사용합니다. GitGatto는 토큰, 비밀번호, 개인 키를 저장하지 않습니다.
- Pull, Push, Fork, 댓글, Review, Actions, 앱 설치, 개발 도구 변경은 앱에서 명시적으로 실행한 경우에만 이루어집니다.

## 개발

macOS 14 이상과 프로젝트에서 선언한 Swift 도구 체인이 필요합니다.

```bash
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
open GitGatto.xcodeproj
```

Swift 6, SwiftUI, AppKit, WebKit, AVKit을 사용합니다. 네트워크는 Alamofire 5.12, 업데이트는 Sparkle 2.9.6을 사용합니다. 기여 규칙은 [CONTRIBUTING.md](CONTRIBUTING.md), 아키텍처 경계는 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)를 참고하세요.

## 감사

- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Alamofire](https://github.com/Alamofire/Alamofire)
- [SwiftUI-Animations](https://github.com/Shubham0812/SwiftUI-Animations)
- [GitHub CLI](https://github.com/cli/cli)
- [Simple Icons](https://github.com/simple-icons/simple-icons), [VSCode Icons](https://github.com/vscode-icons/vscode-icons), [Devicon](https://github.com/devicons/devicon), [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)

정확한 버전과 라이선스는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 있습니다. 보안 문제는 [SECURITY.md](SECURITY.md)의 안내에 따라 신고해 주세요.

## 라이선스

GitGatto는 **ZIJIU522**가 개발하며 [MIT License](LICENSE)로 공개됩니다.
