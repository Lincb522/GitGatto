<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">Un client Git natif piloté par des Agents.</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a>
</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="Dernière version" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon et Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="Licence MIT" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center"><a href="https://gatto.zijiu522.cn">Site web</a> · <a href="https://github.com/Lincb522/GitGatto/releases/latest">Télécharger</a> · <a href="CHANGELOG.md">Journal des versions</a> · <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a></p>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/media/github-project.png" alt="Projet GitHub"><br><sub><b>Projet GitHub</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/workspace.png" alt="Arbre de travail et diff"><br><sub><b>Arbre de travail et diff</b></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="docs/media/recovery-center.png" alt="Centre de récupération"><br><sub><b>Centre de récupération</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/file-time-machine.png" alt="Fichier Time Machine"><br><sub><b>Fichier Time Machine</b></sub></td>
  </tr>
</table>

GitGatto est un client Git et GitHub natif pour macOS. L'état des dépôts vient du Git système, les opérations distantes utilisent GitHub CLI et les Agents s'appuient sur les CLI déjà installées et connectées sur le Mac. GitGatto réunit leurs états, leurs étapes et leurs résultats dans une seule vue de projet.

## Pourquoi GitGatto existe

Une livraison complète passe souvent par le terminal, l'éditeur, GitHub, Actions et la page de version. Lorsqu'une étape échoue, il faut revérifier la branche, les fichiers indexés, les journaux et les artefacts. Avec un Agent, il faut également contrôler son répertoire de travail, ses droits et la correspondance de son contexte avec le dépôt courant.

GitGatto est parti de ces problèmes quotidiens. Il conserve le vrai Git et les outils existants, puis relie les opérations du dépôt, la collaboration GitHub, le travail des Agents et les preuves d'échec dans un parcours que l'on peut vérifier, interrompre et reprendre.

## Fonctions distinctives

### Objectifs de projet

« Livrer les modifications », « Livraison GitHub » et « Version complète » vérifient dans l'ordre des dépendances l'index, les commits, le Push, la Pull Request, les Reviews, Actions, les artefacts, la Release, le DMG, l'Appcast et la version installée. Un objectif peut aussi être décrit en langage naturel, puis ses conditions vérifiées avant l'exécution.

Chaque étape lit l'état réel de Git, GitHub ou du Mac. Les étapes terminées sont conservées après une interruption ; un échec Actions peut être transmis à un Agent avec ses preuves. La fusion, la publication d'un tag et l'installation demandent toujours une confirmation distincte.

### Organisation des changements et preuves

- Le centre des changements classe les modifications par fichier ou bloc de Diff et peut créer plusieurs commits atomiques. Il vérifie l’empreinte du dépôt et crée un point de restauration avant l’exécution ; tout échec de commit ou de vérification restaure le HEAD et la limite de staging d’origine.
- La provenance du code remonte d’une ligne au commit et, si GitHub CLI est disponible, ajoute la Pull Request, les Issues, les Reviews et les Checks associés.
- Les capsules de reproduction regroupent patch, fichiers non suivis, commit de base, commande en échec, sortie et versions des outils dans un fichier `.gatto`. L’import est vérifié puis restauré dans un worktree isolé.
- Le journal d’activité conserve les changements de références Git et d’état des fichiers avec les processus Agent dont le dossier de travail se trouvait dans le dépôt. Le niveau de corrélation est indiqué sans l’assimiler à une responsabilité prouvée.

### Recherche de régression

Exécute `git bisect` dans un worktree isolé sans changer l'espace de travail courant. Le mode automatique lance une commande de vérification ; le mode manuel classe chaque candidat comme bon, défectueux ou ignoré. Commits candidats, codes de sortie, durées et sorties sont conservés. Une fois le premier commit défectueux trouvé, un Agent peut préparer la correction, relancer la vérification et ouvrir une Pull Request.

### Récupération des dépôts

Le centre de récupération surveille les dépôts locaux ajoutés à GitGatto. Il enregistre le travail non commité à intervalles réguliers, crée immédiatement un point de récupération lorsque le nombre de fichiers ou de lignes atteint le seuil, et accepte les sauvegardes manuelles. Un contenu inchangé n'est pas réécrit.

Un point contient un Git bundle du dépôt et une copie des fichiers non commités. Chaque dépôt conserve au plus trois points glissants. Il est possible de consulter l'espace occupé, d'ouvrir les dossiers, de supprimer un point ou toutes les sauvegardes d'un dépôt, puis de restaurer un point dans une nouvelle copie du dépôt. Un changement d'emplacement migre les données existantes et vérifie le résultat avant la bascule.

### Agents spécialisés pour Git

GitGatto prend en charge Codex CLI, Claude Code, Gemini CLI, OpenCode et des modèles de CLI personnalisés. Les opérations de dépôt, la traduction et l'installation de logiciels utilisent des canaux séparés ; une tâche longue ne bloque donc pas la traduction d'un document.

Un Agent peut exploiter la sortie d'erreur complète pour traiter Git, Git LFS, les hooks, la signature, les branches, la synchronisation, les conflits, les Pull Requests et Actions. Si l'index est vide, la rédaction d'un commit peut d'abord indexer les modifications, puis commiter ou commiter et pousser. Une réécriture du README est rendue intégralement avant que « Appliquer le commit » ne commite que ce document.

## Git et GitHub

- Gérer l'arbre de travail, l'index, les commits, Pull, Push, branches, stashes et worktrees.
- Consulter les diffs ligne par ligne, le graphe des commits, Blame, l'historique d'un fichier, ainsi que les images, SVG et vidéos des anciennes révisions.
- Modifier le résultat des conflits de merge, rebase ou stash, puis continuer, ignorer ou abandonner.
- Charger les dépôts accessibles au compte GitHub courant et rechercher dépôts ou développeurs avec recherche approximative, langage naturel et chargement continu.
- Lire code, README, Pull Requests, Actions, Releases et fichiers publiés sans quitter l'application.
- Examiner les fichiers d'une Pull Request, les marquer comme vus, commenter une ligne, répondre, envoyer une Review, relancer ou annuler Actions et télécharger les artefacts.
- Star, Fork et Clone. L'analyse locale est manuelle et permet de choisir les dépôts à ajouter au lieu d'importer tout le disque.

## Documents, traduction et aperçu

- Rendre dans GitGatto le Markdown du dépôt, les images relatives et les liens internes.
- Détecter la langue d'un document et le traduire sur un canal Agent séparé ; les traductions sont conservées localement par version de la source.
- Prévisualiser code source, images, source SVG et médias depuis l'espace de travail, l'historique des commits et celui des fichiers.
- L'Agent README reconstruit le document à partir des fichiers, dépendances et ressources du dépôt au lieu de simplement reformuler le texte.

## Catalogue d'applications et outils de développement

- Rechercher dans GitHub Releases des applications installables avec leur véritable icône, description, captures, version et paquets. Les DMG et ZIP utilisent l'installateur local ; les autres formats passent par un Agent.
- Détecter versions installées et mises à jour pour 99 environnements, outils de build, conteneurs, outils cloud, bases de données et utilitaires CLI.
- Exécuter installations et mises à niveau sur trois voies parallèles avec sélection multiple et traitement par lot. Les modifications Homebrew restent sérialisées afin d'éviter les écritures simultanées dans Cellar.
- Après installation, l'Agent termine le PATH utilisateur, l'enregistrement des composants, l'initialisation et la migration de configuration, puis vérifie à nouveau l'exécutable et sa version.
- Conserver les étapes, la sortie d'origine et une explication localisée des erreurs connues pour le téléchargement, l'installation, la configuration et la vérification.

## Documents du projet

- [Feuille de route](docs/ROADMAP.md) : étapes réalisées, travaux prévus et limites.
- [Architecture](docs/ARCHITECTURE.md) : propriété des états, frontières des services et principaux flux de données.
- [Star History](https://www.star-history.com/#Lincb522/GitGatto&Date) : évolution des étoiles GitHub.

![GitGatto roadmap](docs/media/roadmap.svg)

![GitGatto architecture](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

## Installation

Téléchargez le DMG depuis [Releases](https://github.com/Lincb522/GitGatto/releases/latest), puis glissez GitGatto dans Applications. Les versions sont universelles pour Apple Silicon et Intel et nécessitent macOS 14 ou plus récent.

| Fonction | Prérequis |
| --- | --- |
| Dépôts locaux | Git |
| Dépôts GitHub, PR, Actions et opérations distantes | [GitHub CLI](https://cli.github.com/) connectée |
| Agents | Au moins une CLI prise en charge, installée et connectée |
| Recherche de mises à jour Homebrew | Homebrew |

Les mises à jour intégrées, les notes de version et les installateurs proviennent tous des GitHub Releases de ce dépôt.

## Données locales et autorisations

- Réglages, liste des dépôts, objectifs, enquêtes de régression, conversations et journaux des Agents, téléchargements et traductions restent sur le Mac.
- Lorsque la protection est activée, les Git bundles et copies de fichiers non commités sont conservés dans Application Support ou à l'emplacement choisi. Chaque dépôt garde au plus trois copies, supprimables depuis le centre de récupération.
- Git, SSH, GitHub CLI et les CLI Agent continuent d'utiliser leurs propres identifiants. GitGatto ne stocke ni jeton, ni mot de passe, ni clé privée.
- Pull, Push, Fork, commentaires, Reviews, Actions, installations d'applications et modifications des outils ne s'exécutent qu'après une action explicite dans l'application.

## Développement

macOS 14 ou ultérieur et la chaîne Swift déclarée par le projet sont nécessaires.

```bash
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
open GitGatto.xcodeproj
```

Le code utilise Swift 6, SwiftUI, AppKit, WebKit et AVKit ; Alamofire 5.12 pour le réseau et Sparkle 2.9.6 pour les mises à jour. Voir [CONTRIBUTING.md](CONTRIBUTING.md) pour contribuer et [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) pour les limites du système.

## Remerciements

- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Alamofire](https://github.com/Alamofire/Alamofire)
- [SwiftUI-Animations](https://github.com/Shubham0812/SwiftUI-Animations)
- [GitHub CLI](https://github.com/cli/cli)
- [Simple Icons](https://github.com/simple-icons/simple-icons), [VSCode Icons](https://github.com/vscode-icons/vscode-icons), [Devicon](https://github.com/devicons/devicon) et [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)

Les versions et licences exactes figurent dans [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Signalez les problèmes de sécurité par le canal indiqué dans [SECURITY.md](SECURITY.md).

## Licence

GitGatto est développé par **ZIJIU522** et publié sous [licence MIT](LICENSE).
