<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">macOS · Git · GitHub</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a>
</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="Neueste Version" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon und Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT-Lizenz" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center"><a href="https://gatto.zijiu522.cn">Website</a> · <a href="https://github.com/Lincb522/GitGatto/releases/latest">Download</a> · <a href="CHANGELOG.md">Änderungsprotokoll</a> · <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a></p>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/media/github-project.png" alt="GitHub-Projekt"><br><sub><b>GitHub-Projekt</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/workspace.png" alt="Arbeitsbaum und Diff"><br><sub><b>Arbeitsbaum und Diff</b></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="docs/media/recovery-center.png" alt="Wiederherstellungszentrale"><br><sub><b>Wiederherstellungszentrale</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/file-time-machine.png" alt="File Time Machine"><br><sub><b>File Time Machine</b></sub></td>
  </tr>
</table>

GitGatto ist ein nativer Git- und GitHub-Client für macOS auf Apple Silicon und Intel. Neben Repository-Arbeit bietet er Sicherungen nicht committeter Dateien, Aktivitäten externer Agents, Lieferziele, Regressionssuche und die Einrichtung von Entwicklungswerkzeugen.

<a id="why"></a>
## Warum wir GitGatto entwickeln

Nach dem Programmieren bleiben gemischte Änderungen, Regressionen, CI, PR-Reviews und Releases. Beim Aufgabenwechsel gehen außerdem leicht Entwürfe und nicht committete Dateien aus dem Blick.

Mit Agents kommen Fragen dazu: Was wurde warum geändert? Welche Fehlerbelege bleiben? Funktioniert das als fertig gemeldete Ergebnis? GitGatto soll diese Arbeit und ihre Wiederaufnahme unterstützen, nicht nur Git-Befehle mit Buttons versehen. System-Git und vorhandene CLIs bleiben erhalten; Änderungen, Belege und Wiederherstellungspunkte sind einsehbar.

[Sicherung](#recovery) · [Menüleiste](#monitoring) · [Ziele](#goals) · [Commits aufteilen](#intent) · [Regression](#regression) · [Projektwerkzeuge](#project-tools) · [Installation](#install-tools)

<a id="features"></a>
## Besondere Funktionen

<a id="recovery"></a>
### Nicht committete Arbeit sichern, externe Änderungen beobachten

Registrierte lokale Repositories werden zeitgesteuert, bei großen Änderungen oder manuell gesichert; identische Inhalte werden übersprungen. Pro Repository rotieren höchstens drei Wiederherstellungspunkte aus Git-Bundle und nicht committeten Dateien.

Vor Schreibzugriffen des internen Agents kann ein Punkt entstehen. Der Repository-Wächter beobachtet auch Löschungen, verlorene Änderungen, zurückgesetzte Referenzen und nicht verfügbare Repositories nach Aktivitäten externer Agents, Terminals oder Skripte. Meldungen zeigen Gründe und Pfade, beweisen aber keine Verursachung durch einen bestimmten Prozess.

Gestaffeltes Schreiben und Abschlussmarkierungen unterscheiden nach einem Abbruch unvollständige Kopien von gültigen Sicherungen. Speicher prüfen, einzelne oder Repository-Sicherungen löschen und beim Verzeichniswechsel migrieren. Wiederherstellung schreibt eine neue Kopie, nicht über das Original. Keine systemweite Befehlsblockade und keine Wiederherstellungsgarantie für ungespeicherte oder ausgeschlossene Dateien.

<a id="monitoring"></a>
### Repository-Status in der Menüleiste

Alle oder einzelne Repositories unabhängig vom Hauptfenster auswählen: Änderungen, Upstream, Wiederherstellungspunkte, Actions, Ziele und tägliche Aktivität eines Jahres. Die Punkte zählen Commits und beobachtete Änderungen, keine Arbeitszeit.

Einstellungen enthalten separate Schalter für Arbeitsbaum, Remote, Schutz, Actions und Ziele sowie Gesamtschalter, Menüleistensichtbarkeit und Intervalle. Überwachung läuft bei geöffnetem Hintergrundprozess weiter, endet aber beim Beenden der App.

<a id="goals"></a>
### Lieferziele unterbrechen und fortsetzen

Aktuelle Änderungen liefern, GitHub-Lieferung, vollständiges Release oder natürlichsprachliches Ziel wählen. Schritte vorab prüfen; Fortschritt, Blockaden und Aufzeichnungen verfolgen, aktive und frühere Ziele suchen und filtern.

Je nach Ablauf werden Staging, Commit, Push, PR, Review, Actions, Artefakte, Release, DMG, Appcast und installierte Version geprüft. Agent-Vorschläge für eigene Bedingungen müssen bestätigt werden. Nach Unterbrechungen wird der tatsächliche Zustand erneut gelesen. Agent-Text gilt nicht als Erfolgsbeweis; Merge, Tag-Veröffentlichung und Installation bleiben separat zu bestätigen.

<a id="intent"></a>
### Gemischte Änderungen in Commits aufteilen

Dateien oder Diff-Hunks gruppieren, Nachrichten festlegen oder einen Agent beim Gruppieren helfen lassen. Vor der Ausführung werden fehlende oder doppelte Zuordnungen und Repository-Änderungen geprüft, dann ein Wiederherstellungspunkt erstellt und der Reihe nach committet.

Jeder Commit erhält eine Diff-Prüfung oder einen eigenen Prüfbefehl. Bei Fehlern wird die Rückkehr zu ursprünglichem HEAD und Staging-Grenze versucht, nicht unter allen Umständen garantiert; der Sicherungspunkt bleibt prüfbar.

<a id="regression"></a>
### Regressionen im separaten Worktree untersuchen

`git bisect` wechselt nicht Ihr Arbeitsverzeichnis. Automatisch per Prüfbefehl oder manuell als gut, fehlerhaft oder übersprungen bewerten; Kandidaten, Urteile, Exitcodes, Laufzeit und Ausgabe speichern. Belege können an einen Agent für Korrektur, Nachprüfung und PR-Vorbereitung gehen. Der Test muss den Fehler erkennen; viele übersprungene Commits können mehrere Kandidaten übrig lassen.

<a id="evidence"></a>
### Codeherkunft, Fehlerkapseln und Aktivitäten

- **Codeherkunft:** Zeile zum Commit verfolgen; mit GitHub CLI verknüpfte PRs, Issues, Reviews und Checks sehen.
- **Fehlerkapseln:** Basiscommit, Patches, zulässige unversionierte Dateien, Fehlerbefehl, Ausgabe und Toolversionen als `.gatto` exportieren. Struktur und Hashes vor Wiederherstellung im separaten Worktree prüfen; enthaltene Befehle laufen nicht automatisch. Nur bekannte sensible Pfade und erkannte Inhalte werden gefiltert: vor dem Teilen prüfen.
- **Externe Agents:** Datei- und Referenzänderungen mit bekannten, im Repository arbeitenden Agent-Prozessen und Belegstärke verbinden. Gleichzeitige Ausführung beweist keine Verantwortung.

<a id="agent"></a>
### Agents für mehr als Commit-Nachrichten

Codex CLI, Claude Code, Gemini CLI, OpenCode und eigene CLIs sind möglich. Git-Anleitungen decken Staging-Review, Commit-Entwürfe, Konflikte, Branchpflege, Verlaufsrettung, Repository-Gesundheit und Release-Prüfung ab. Originalfehler von LFS, Hooks, Signaturen und Synchronisierung können mitgegeben werden.

Projektarbeit, Übersetzung, Suche und Installation nutzen getrennte Ausführungspfade. README-Neufassungen erst ansehen, dann anwenden. Issue- und PR-Antworten aus Diskussion und Diff bleiben editierbare Entwürfe und werden erst nach Bestätigung gesendet. Vorhandene CLI- und Modellkonfigurationen bleiben nutzbar.

<a id="project-tools"></a>
### Beim Aufgabenwechsel mehr als den Branch behalten

**Arbeitsstände** speichern vorgemerkte, nicht vorgemerkte und unversionierte Dateien, Branch, Entwürfe, Dateiauswahl, Ziele und Links. Wiederherstellung prüft den Repository-Zustand; Öffnen im eigenen Worktree ist möglich. Ignorierte Dateien fehlen, ein Arbeitsstand ist keine unabhängige Sicherung.

| Werkzeug | Funktion |
| --- | --- |
| Codesuche | Aktuelle Dateien, Revisionen und historische Änderungen über verwaltete Repositories durchsuchen; nach Verzeichnis, Sprache oder Erweiterung filtern und Belege an einen Agent geben. Wörtliche Suche mit Ergebnisgrenzen. |
| Befehle ausführen | Projektskripte finden, eigene Befehle hinzufügen und anheften; Ausgabe, Zeit, Status, Stoppen, Wiederholen und lokale Dienste öffnen. Nichtinteraktiv, Argumente als JSON-Array. |
| Ignorierregeln | Herkunft erklären, Änderungen an `.gitignore` oder `.git/info/exclude` vorab prüfen. Tracking beenden, Dateien behalten. |
| Commit-Identitäten | Autor und Signatur pro Repository oder Verzeichnis zuordnen; wirksame Quellen und Identität vor dem Commit prüfen. Von GitHub-Anmeldung getrennt. |

Über Projektwerkzeuge oder `⌘K` öffnen.

<a id="install-tools"></a>
### Installation samt Einrichtung und Überprüfung

Der Anwendungskatalog findet GitHub-Releases und unterscheidet Download und Installation. DMG/ZIP werden nativ, Kommandozeilenpakete per Agent installiert. Phasen, Ausgabe und Wiederholung sind sichtbar.

**99 Werkzeuge und Laufzeiten**, lokale Versionserkennung, Mehrfachauswahl und Stapel-Upgrades. Installations- und Upgrade-Warteschlangen erlauben drei parallele Aufgaben; Homebrew-Schreibzugriffe bleiben seriell.

Erforderliche PATH-Einträge, Pluginregistrierung, Initialisierung und Konfigurationsmigration werden vor der Prüfung von Programmdatei und Version erledigt. Download oder Agent-Erfolgsmeldung ersetzen diese Prüfung nicht. Offene Rechte- und Konfigurationsschritte bleiben sichtbar; Anmeldung und Systemfreigabe benötigen den Benutzer. Die Liste installierter Apps erfasst GitGatto-Installationen, nicht sämtliche Mac-Apps.

<a id="git-github"></a>
## Tägliche Git- und GitHub-Arbeit

- Staging, Commits, Diff, Graph, Blame, Datei- und Medienhistorie; kombinierte Suche nach SHA, Autor, Pfad, Text, Datum und Referenz.
- Branches, Tags, Remotes, Stashes, Worktrees, Referenzvergleich und Rettungsbranches aus Reflog. Umordnen, Squash, Aufteilen, Amend, Cherry-pick, Revert und Reset; veröffentlichte Commits werden vor Umschreibung geprüft, destruktive Aktionen bestätigt.
- Merge-, Rebase- und Stash-Konflikte bearbeiten; fortsetzen, überspringen, abbrechen; LFS, Hooks und Umgebung prüfen.
- Mehrere Repositories abrufen, pullen und pushen; Vorsprung, Rückstand, Divergenz, Konflikte und Fehler getrennt sehen und Fehler wiederholen.
- Kontorepositories, Entwickler- und natürlichsprachliche Suche, Star, Fork, Klonen, Code, README, Releases und Anhänge.
- Posteingang für Reviews, Erwähnungen und fehlgeschlagene Checks; Issues erstellen und bearbeiten; PR-Dateien, Gelesen-Markierungen, Zeilenkommentare, Antworten und Reviews.
- Actions-Läufe und Logs, Wiederholen, Abbrechen, Artefakte. Aktualisieren einer Seite löst keinen Remote-Schreibzugriff aus.

<a id="reading"></a>
## Lesen und übersetzen

Markdown, relative Bilder, Quelltext, SVG und Medien direkt ansehen. Spracherkennung und separate Übersetzungskonfiguration; Cache nach Original, Pfad und Zielsprache, keine veraltete Übersetzung nach Quelländerungen. Bereits passende Sprache oder zu kurzer Text können unverändert bleiben. Kein automatischer README-Commit.

<a id="appearance"></a>
## Themen und Oberfläche

Sechs Themen: Leichter Nebel, Weiches Milchglas, Konsole, Smaragd, Folio, Lichtbühne. Unterschiede betreffen Layout, Panels, Seitenleiste und Bedienelemente. Lichtbühne erlaubt getrennte Hell-/Dunkelfarben für Hintergrund, Panels, Text, Buttons und Status, mit Koralle, Küste, Wald, Abend als Voreinstellungen.

Einklappbare, scrollbare Seitenbereiche, veränderbare Arbeitsflächen und 11 Sprachen ohne Neustart. Anleitung in der Hilfe der App.

<a id="start"></a>
## Installation und Einstieg

DMG aus [Releases](https://github.com/Lincb522/GitGatto/releases/latest) laden und nach Programme ziehen. macOS 14+, Apple Silicon/Intel. Veröffentlichungen stehen in [Changelog](CHANGELOG.md) und Releases; diese README beschreibt den aktuellen Repository-Stand.

| Einsatz | Voraussetzung |
| --- | --- |
| Git und normale Remote-Synchronisierung | Git und passende Git-/SSH-Authentifizierung |
| GitHub, PRs, Issues, Actions | Angemeldete [GitHub CLI](https://cli.github.com/) |
| Agent, Übersetzung, Agent-Installation | Installierte CLI mit erforderlicher Anmeldung/Konfiguration |
| Homebrew-Erkennung und Updates | Homebrew |

Repository öffnen oder manuell scannen und auswählen, kein automatischer Gesamtimport der Festplatte. GitHub und Agents in Einstellungen konfigurieren; App-Updates kommen aus GitHub Releases und Appcast.

<a id="data"></a>
## Daten und Rechte

Listen, Einstellungen, Ziele, Untersuchungen, Gespräche, Übersetzungen, Downloadverlauf und Sicherungen liegen lokal; Sicherungsspeicher ist verschiebbar. Git, SSH und CLIs behalten ihre Authentifizierungsquellen.

Lokale Speicherung bedeutet nicht vollständig offline: GitHub wird kontaktiert, Agent und Übersetzung geben benötigten Kontext an die konfigurierte CLI. Weitere Verarbeitung hängt vom Tool und Modelldienst ab. Inhalte prüfen und keine Zugangsdaten in Befehle, Entwürfe oder Kapseln schreiben. Systemverzeichnisse unterliegen macOS-Freigaben.

<a id="docs"></a>
## Planung, Architektur und Verlauf

[Roadmap](docs/ROADMAP.md) · [Architektur](docs/ARCHITECTURE.md) · [Versionen](CHANGELOG.md)

![GitGatto Roadmap](docs/media/roadmap.svg)

![GitGatto Architektur](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

Die Roadmap beruht auf Versionsaufzeichnungen; gestrichelte Bereiche sind Pläne. Star History ist ein gespeicherter Datenstand, der Bildlink öffnet die Onlineaufzeichnung.

<a id="development"></a>
## Aus Quellcode starten

macOS 14+, Swift 6.1+; Xcode-Konfiguration in `project.yml`.

```sh
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
swift run GitGatto
```

Alternativ `GitGatto.xcodeproj` mit Scheme `GitGatto` öffnen. Strukturänderungen über XcodeGen und `./scripts/generate-xcodeproj.sh` erzeugen, Projektdatei nicht manuell bearbeiten. SwiftUI, AppKit, WebKit, AVKit, Alamofire und Sparkle; Versionen in `Package.resolved`.

<a id="credits"></a>
## Beiträge und Lizenz

[Beitragen](CONTRIBUTING.md) · [Sicherheit](SECURITY.md). Danke an [GitHub CLI](https://github.com/cli/cli), [Sparkle](https://github.com/sparkle-project/Sparkle), [Alamofire](https://github.com/Alamofire), [Reicon](https://github.com/Lincb522/reicon) sowie Icon- und Animationsautoren. Quellen: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Entwickelt von **ZIJIU522**, veröffentlicht unter [MIT License](LICENSE).
