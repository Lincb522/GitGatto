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

스크린샷은 데모 데이터로 화면을 보여 줍니다. 프로젝트 이름과 수치는 실제 사용 지표가 아닙니다.

GitGatto는 Apple Silicon과 Intel을 지원하는 macOS 네이티브 Git·GitHub 클라이언트입니다. 일반 저장소 작업 외에 미커밋 코드 백업, 외부 Agent 활동 기록, 목표별 전달·릴리스, 회귀 조사, 개발 도구 설치와 설정을 제공합니다.

<a id="why"></a>
## GitGatto를 만든 이유

코드를 작성한 뒤에도 섞인 변경 정리, 회귀가 시작된 커밋 찾기, CI 확인, PR 검토와 릴리스가 남습니다. 잠시 다른 작업으로 옮겼다가 초안이나 미커밋 파일을 놓치기도 합니다.

Agent를 쓰면 무엇을 왜 바꿨는지, 실패한 증거는 어디 있는지, 완료했다는 결과가 실제로 작동하는지도 확인해야 합니다. GitGatto는 Git 명령에 버튼만 붙이기보다 이 작업과 복구를 다루려고 만들었습니다. 시스템 Git과 기존 CLI를 그대로 쓰면서 변경, 증거, 복구 지점, 후속 작업을 확인할 수 있습니다.

[복구](#recovery) · [모니터링](#monitoring) · [목표](#goals) · [변경 분할](#intent) · [회귀](#regression) · [프로젝트 도구](#project-tools) · [설치](#install-tools)

<a id="features"></a>
## 주요 기능

<a id="recovery"></a>
### 미커밋 코드 백업과 외부 Agent 보호

등록한 로컬 저장소의 Git bundle과 미커밋 파일을 백업합니다. 정기·대규모 변경 백업은 변하지 않은 내용을 건너뛰며 수동 생성도 가능합니다. 저장소마다 최대 세 세대를 순환 보관합니다.

앱 안의 Agent가 쓰기 전에 복구 지점을 만들 수 있습니다. 외부 Agent, 터미널, 스크립트가 만든 삭제, 변경 소실, 참조 되돌림과 저장소 사용 불가를 감지해 이유와 경로를 표시합니다. 백업 파일 확인·비교·선택 내보내기, 새 디렉터리 복원, 저장 위치 변경 시 이전을 지원합니다.

정전 복구는 마지막으로 완료된 지점을 기준으로 합니다. 내용과 목록을 디스크에 동기화한 뒤 완료 표식을 동기화하고 이전 세대를 정리합니다. 중단된 쓰기는 다음 시작 때 처리합니다. 마지막 백업 이후 수정, 편집기의 미저장 내용과 제외된 파일은 복구를 보장하지 않습니다. 다른 앱의 모든 명령을 차단하는 기능은 아닙니다.

<a id="monitoring"></a>
### 메뉴 막대에서 저장소 상태 확인

주 창과 독립적으로 전체 또는 개별 저장소의 변경, 업스트림 상태, 복구 지점, Actions, 목표, 일별 활동을 봅니다. 접힌 표시에도 범위·변경 수·알림이 나오며 펼친 패널은 스크롤과 앱 테마를 지원합니다. 활동은 커밋과 감지한 변경 수이며 근무 시간이 아닙니다.

설정에서 종료 후 모니터링을 켜면 독립 도우미가 앱 종료 후에도 모니터링, 정기·대규모 변경 백업과 저장소 보호를 기존 설정대로 이어갑니다. 앱을 다시 열면 작업을 넘겨 중복 스캔을 피합니다. 기본값은 꺼짐이며 macOS 승인이 필요할 수 있습니다.

전체·개별 채널·메뉴 막대 표시·주기를 각각 설정합니다. 아이콘을 숨겨도 켜진 백그라운드 백업은 유지됩니다. 전체 모니터링이나 저장소 보호를 끄면 해당 작업이 중지됩니다.

<a id="goals"></a>
### 중단 후 이어가는 전달 목표

커밋 및 푸시, PR 만들기, 릴리스 발행 또는 사용자 정의 목표를 선택합니다. 변경·Issue·PR·실패한 검사에서도 시작할 수 있습니다. 현재 진행 상황을 우선 표시하고 상세 단계와 기록은 펼쳐서 봅니다.

선택한 흐름에 따라 스테이징, 커밋, Push, PR, Review, Actions, 산출물, Release, DMG, Appcast와 로컬 버전을 확인합니다. 사용자 정의 조건은 Agent 제안에 동의한 뒤 실행합니다. 중단 후 실제 상태를 다시 읽으며 Agent 답변 자체를 성공으로 보지 않습니다. 병합, 태그 게시, 설치는 별도 확인이 필요합니다.

<a id="intent"></a>
### 섞인 변경을 여러 커밋으로

파일이나 Diff hunk를 그룹으로 묶고 커밋 메시지를 각각 작성하거나 Agent에 정리를 맡깁니다. 누락·중복 할당과 저장소 변경을 검사하고 복구 지점을 만든 뒤 순서대로 커밋합니다.

각 커밋에서 diff 검사 또는 지정한 검증 명령을 실행합니다. 실패하면 원래 HEAD와 스테이징 경계로 복구를 시도하지만 모든 오류에서 성공을 보장하지는 않습니다. 복구 지점으로 상태를 확인할 수 있습니다.

<a id="regression"></a>
### 독립 worktree에서 회귀 조사

현재 작업 디렉터리를 전환하지 않고 `git bisect`를 실행합니다. 자동 모드는 검증 명령을 사용하고 수동 모드는 정상·오류·건너뜀을 선택합니다. 후보, 판정, 종료 코드, 소요 시간과 출력을 보관합니다.

증거를 Agent에 넘겨 수정, 재검증, PR 준비로 이어갈 수 있습니다. 명령이 실제 문제를 판별해야 하며, 건너뛴 커밋이 많으면 후보를 하나로 좁히지 못할 수 있습니다.

<a id="evidence"></a>
### 코드 근거, 실패 캡슐, 활동 기록

- **코드 근거**: 파일 행에서 커밋을 추적하고 GitHub CLI가 있으면 관련 PR, Issue, Review, Checks까지 확인합니다.
- **실패 캡슐**: 기준 커밋, 패치, 허용된 미추적 파일, 실패 명령, 출력과 도구 버전을 `.gatto`로 내보냅니다. 가져올 때 구조와 해시를 검사한 뒤 독립 worktree에 복원하며 포함된 명령을 자동 실행하지 않습니다. 알려진 민감 경로와 식별 가능한 내용만 걸러내므로 공유 전 확인해야 합니다.
- **외부 Agent 활동**: 파일·참조 변화를 당시 저장소에서 작업한 알려진 Agent 프로세스와 연결하고 증거 강도를 표시합니다. 실행 중이었다는 이유만으로 모든 변경의 책임이 입증되지는 않습니다.

<a id="agent"></a>
### 커밋 초안 이상을 다루는 Agent

Codex CLI, Claude Code, Gemini CLI, OpenCode, DeepSeek Harness (dsh), Cursor Agent, GitHub Copilot CLI, Qwen Code, 사용자 정의 CLI를 지원합니다. 내장 Git 지침으로 스테이징 검토, 커밋 작성, 충돌, 분기 정리, 기록 복구, 저장소 상태와 릴리스를 확인합니다. LFS·hooks·서명·동기화의 원본 오류도 함께 조사할 수 있습니다.

프로젝트, 번역, 검색, 설치는 별도 실행 경로입니다. README 재작성은 미리 보고 적용합니다. Issue·PR 답변은 논의와 diff를 바탕으로 편집 가능한 초안을 만들고 확인 후 전송합니다. 기존 CLI와 모델 설정을 계속 사용할 수 있습니다.

OpenAI 호환 API나 DeepSeek API를 직접 설정할 수도 있으며 API 모드에는 CLI 설치가 필요하지 않습니다. 프로젝트와 번역의 주소·모델을 따로 선택하고 모델 목록, 기능 점검, 스트리밍 응답을 사용합니다. 키는 macOS 키체인에 저장됩니다. API Agent는 프로젝트 읽기, 명령 실행, 통제된 경로의 쓰기를 지원하며 번역에는 쓰기 도구를 제공하지 않습니다.

<a id="project-tools"></a>
### 분기뿐 아니라 작업 상태도 저장

**작업 상태**은 스테이징·미스테이징·미추적 파일, 분기, 초안, 선택 파일, 관련 목표와 링크를 보관합니다. 복원 시 저장소 상태를 확인하고 독립 worktree에서도 열 수 있습니다. 무시된 파일은 제외되며 독립 백업을 대신하지 않습니다.

| 도구 | 기능 |
| --- | --- |
| 코드 검색 | 관리 저장소의 현재 파일, 지정 버전, 과거 변경을 검색하고 디렉터리·언어·확장자로 필터링합니다. 증거를 미리 보고 Agent에 넘깁니다. 정규식이 아닌 일반 문자열 검색이며 결과 수가 제한됩니다. |
| 명령 실행 | 프로젝트 스크립트 감지, 사용자 정의·고정, 실시간 출력·시간·종료 상태 확인, 중지·재시도·로컬 서비스 열기. 비대화형이며 인자는 JSON 배열입니다. |
| 제외 규칙 | 규칙 출처 확인, 미리 보기 후 공유 `.gitignore` 또는 로컬 `.git/info/exclude` 편집. 추적 해제 시 디스크 파일 유지. |
| 커밋 사용자 정보 | 저장소·디렉터리별 작성자와 서명 설정, 적용 출처 및 커밋 전 일치 검사. GitHub 로그인과 별개입니다. |

도구 막대의 프로젝트 도구 또는 `⌘K`로 엽니다.

<a id="install-tools"></a>
### 설치 뒤 설정과 검증까지

GitHub Releases에서 버전과 파일을 찾고 다운로드와 설치를 구분합니다. DMG·ZIP은 네이티브 설치, 명령줄 패키지는 Agent가 처리합니다. 관리 화면에서 단계, 출력, 재시도를 확인합니다.

**99개 도구와 런타임**의 로컬 버전을 감지하고 다중 선택·일괄 업그레이드를 지원합니다. 설치·업그레이드 큐는 최대 세 작업을 병렬 처리하며 Homebrew 쓰기는 직렬화합니다.

필요한 PATH, 플러그인 등록, 초기화, 설정 이전 후 실행 파일과 실제 버전을 검사합니다. 다운로드 완료나 Agent 보고로 검증을 대신하지 않습니다. 권한·설정 미완료 항목을 남기고 로그인과 시스템 승인은 사용자가 합니다. 설치됨 목록은 GitGatto 설치 기록이며 Mac의 모든 앱을 수집한 목록이 아닙니다.

<a id="git-github"></a>
## 일상적인 Git·GitHub 작업

- 스테이징, 커밋, Diff, 그래프, Blame, 파일·미디어 기록. SHA·작성자·경로·텍스트·날짜·참조 복합 검색.
- 분기, 태그, 원격, stash, worktree, 참조 비교와 reflog 복구 분기. 재정렬·합치기·분할·수정·cherry-pick·revert·reset. 기록 재작성은 게시된 커밋을 검사하며 파괴적 작업은 확인을 요구합니다.
- merge·rebase·stash 충돌 편집과 계속·건너뛰기·중단, LFS·hooks·도구 진단.
- 여러 저장소 fetch·pull·push, 앞섬·뒤처짐·분기·충돌·실패별 결과와 실패 재시도.
- 계정 저장소, 개발자·자연어 검색, Star, Fork, clone, 코드, README, Release와 첨부.
- 받은 편지함의 리뷰·언급·실패 검사, Issue 생성·관리, PR 파일 검토·열람 표식·행 댓글·답변·Review.
- Actions 실행·로그·재실행·취소·산출물 다운로드. 페이지 새로고침으로 원격 쓰기를 실행하지 않습니다.

<a id="reading"></a>
## 읽기와 번역

Markdown, 상대 경로 이미지, 소스, SVG, 미디어를 앱에서 봅니다. 언어 감지 후 독립 설정으로 번역하며 원문·경로·대상 언어별로 캐시합니다. 원문이 바뀌면 이전 번역을 재사용하지 않습니다. 이미 대상 언어이거나 너무 짧으면 원문을 유지할 수 있고 README를 자동 커밋하지 않습니다.

<a id="appearance"></a>
## 테마와 화면

라이트 미스트, 부드러운 반투명 유리, 콘솔, 에메랄드, 폴리오, 루멘의 여섯 테마는 배치, 패널, 사이드바, 컨트롤도 다릅니다. 루멘은 밝고 어두운 모드의 배경·패널·문자·버튼·상태 색을 따로 설정하며 코랄, 해안, 숲, 황혼 프리셋을 제공합니다.

사이드바 접기·스크롤과 작업 영역 크기 조정을 지원합니다. 11개 언어를 재시작 없이 전환하며 앱의 도움말에서 사용법을 확인합니다.

<a id="start"></a>
## 설치와 시작

[Releases](https://github.com/Lincb522/GitGatto/releases/latest)의 DMG를 열어 응용 프로그램으로 옮깁니다. macOS 14+, Apple Silicon·Intel 지원. 게시된 버전은 [변경 기록](CHANGELOG.md)과 Release를, 현재 저장소 기능은 이 README를 참고하세요.

| 용도 | 필요 사항 |
| --- | --- |
| 로컬 Git·일반 원격 동기화 | Git 및 해당 원격의 Git / SSH 인증 |
| GitHub·PR·Issue·Actions | 로그인된 [GitHub CLI](https://cli.github.com/) |
| Agent·번역·Agent 설치 | 설정된 CLI 또는 OpenAI 호환 / DeepSeek API, 선택 작업을 지원하는 모델과 권한 |
| Homebrew 감지·업그레이드 | Homebrew |

로컬 저장소를 열거나 수동 스캔으로 선택해 추가합니다. 전체 디스크 자동 등록은 없습니다. 설정에서 GitHub·Agent를 구성하고 GitHub Releases와 Appcast로 업데이트합니다.

<a id="data"></a>
## 데이터와 권한

설정, 저장소 목록, 목표, 조사, 대화, 번역, 다운로드 기록, 복구 지점은 로컬에 저장하며 백업 위치를 옮길 수 있습니다. Git·SSH·GitHub CLI·Agent CLI의 기존 인증 출처를 사용합니다.

로컬 저장이 완전 오프라인을 뜻하지는 않습니다. GitHub에 접속하고 Agent·번역에 필요한 맥락을 설정한 CLI 또는 API에 전달합니다. 이후 처리는 도구와 모델 서비스에 따릅니다. 전송 내용을 확인하고 명령·초안·캡슐에 자격 증명을 넣지 마세요. 시스템 디렉터리 변경에는 macOS 승인이 필요합니다.

<a id="docs"></a>
## 계획·구조·개발 기록

[로드맵](docs/ROADMAP.md) · [아키텍처](docs/ARCHITECTURE.md) · [변경 기록](CHANGELOG.md)

![GitGatto 로드맵](docs/media/roadmap.svg)

![GitGatto 구조](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

로드맵은 소스와 버전 기록을 따르며 점선은 계획입니다. Star 그래프는 2026-09-12 UTC의 현재 Stargazers 날짜를 누적하며 취소된 Star는 포함하지 않습니다. 클릭하면 온라인 기록을 엽니다.

<a id="development"></a>
## 소스에서 실행

macOS 14+, Swift 6.1+가 필요하며 Xcode 설정은 `project.yml`에 있습니다.

```sh
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test --no-parallel
swift run GitGatto
```

`GitGatto.xcodeproj`의 `GitGatto` scheme도 사용할 수 있습니다. 구조 변경은 XcodeGen으로 `./scripts/generate-xcodeproj.sh`를 실행해 반영하며 생성 파일을 직접 편집하지 않습니다. SwiftUI, AppKit, WebKit, AVKit, Alamofire, Sparkle을 사용하고 `Package.resolved`에 버전을 고정합니다.

<a id="credits"></a>
## 기여와 라이선스

[기여 안내](CONTRIBUTING.md)·[보안](SECURITY.md)을 참고하세요. [GitHub CLI](https://github.com/cli/cli), [Sparkle](https://github.com/sparkle-project/Sparkle), [Alamofire](https://github.com/Alamofire), [Reicon](https://github.com/Lincb522/reicon) 및 아이콘·애니메이션 제작자께 감사합니다. 전체 출처는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 있습니다.

**ZIJIU522**가 개발하며 [MIT License](LICENSE)로 공개합니다.
