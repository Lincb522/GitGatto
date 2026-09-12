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

Les captures présentent l’interface avec des données de démonstration. Les noms de projets et les compteurs ne sont pas des statistiques d’utilisation.

GitGatto est un client Git et GitHub natif pour macOS, sur Apple Silicon et Intel. Il propose aussi la sauvegarde du code non committé, le suivi des Agents externes, des objectifs de livraison, la recherche de régressions et la configuration d'outils de développement.

<a id="why"></a>
## Pourquoi nous développons GitGatto

Après le code restent les modifications à démêler, les régressions à retrouver, la CI, les revues et les releases. Un changement de tâche peut aussi faire perdre de vue brouillons et fichiers non committés.

Les Agents ajoutent des questions : qu'ont-ils changé, pourquoi, quelles traces reste-t-il après un échec et le résultat annoncé fonctionne-t-il ? GitGatto traite ces tâches et leur reprise, pas seulement l'habillage des commandes Git. Il conserve Git système et les CLI existantes tout en donnant accès aux modifications, preuves et points de restauration.

[Sauvegarde](#recovery) · [Barre des menus](#monitoring) · [Objectifs](#goals) · [Organisation des commits](#intent) · [Régressions](#regression) · [Outils](#project-tools) · [Installation](#install-tools)

<a id="features"></a>
## Fonctions distinctives

<a id="recovery"></a>
### Sauvegarder le travail non committé et observer les changements externes

Les dépôts locaux ajoutés disposent de Git bundles et de copies des fichiers non committés. Les sauvegardes programmées ou déclenchées par de gros changements ignorent le contenu inchangé ; des points manuels restent possibles. Trois générations maximum par dépôt.

Créer un point avant les écritures de l’Agent. La protection observe suppressions, modifications perdues, références reculées et dépôts indisponibles après des changements externes, avec raisons et chemins. Inspecter, comparer ou exporter des fichiers, restaurer dans un nouveau dossier ; changer de destination migre les sauvegardes existantes.

Après une coupure de courant, la récupération repose sur le dernier point complet. Contenu et manifeste sont synchronisés avant le marqueur de fin, puis les anciennes copies sont renouvelées. Les écritures interrompues sont traitées au démarrage. Les modifications ultérieures, non enregistrées dans l’éditeur ou exclues ne sont pas garanties récupérables. La protection ne bloque pas toutes les commandes d’autres applications.

<a id="monitoring"></a>
### Voir les dépôts depuis la barre des menus

Choisir tous les dépôts ou un seul, indépendamment de la fenêtre principale : modifications, amont, sauvegardes, Actions, objectifs et activité quotidienne. L’affichage réduit indique aussi périmètre, nombre de changements et alertes. Le panneau défile et suit le thème. L’activité compte les commits et changements observés, pas le temps de travail.

Activer la surveillance après fermeture permet à un assistant indépendant de reprendre surveillance, sauvegardes programmées ou importantes et protection selon les réglages. À la réouverture, les tâches reviennent à l’application sans doubles analyses. Désactivé par défaut ; macOS peut demander une approbation.

Activation générale, canaux, visibilité et intervalles sont séparés. Masquer l’icône n’arrête pas les sauvegardes actives. Désactiver le moteur ou la protection arrête les tâches correspondantes.

<a id="goals"></a>
### Reprendre un objectif de livraison

Choisir Commit et Push, Créer une PR, Publier une version ou Personnalisé, également depuis des changements, une Issue, une PR ou un check en échec. La progression reste visible ; étapes et historique se déplient au besoin.

Selon le parcours, vérifier index, commit, Push, PR, Review, Actions, artefacts, Release, DMG, Appcast et version installée. Les conditions proposées par l'Agent doivent être approuvées. Après interruption, l'état réel est relu ; son texte ne prouve pas la réussite. Fusion, publication de tags et installation gardent leurs confirmations séparées.

<a id="intent"></a>
### Séparer les modifications en plusieurs commits

Regrouper fichiers ou hunks avec leur message, avec l'aide possible d'un Agent. Avant exécution, vérifier omissions, doublons et changement du dépôt, créer un point de restauration puis committer dans l'ordre.

Chaque commit passe un contrôle de diff ou une commande de vérification choisie. En cas d'échec, retour tenté vers le HEAD et l'index d'origine, sans garantie dans toutes les situations ; le point de restauration reste consultable.

<a id="regression"></a>
### Chercher une régression dans un worktree isolé

Exécuter `git bisect` sans changer le dossier de travail courant. Automatiquement par une commande ou manuellement avec bon, défectueux ou ignoré. Candidats, verdicts, codes de sortie, durée et sortie sont conservés.

Transmettre les preuves à un Agent pour correction, nouvelle vérification et préparation d'une PR. La commande doit reconnaître le problème ; trop de commits ignorés peuvent laisser plusieurs candidats.

<a id="evidence"></a>
### Origine du code, capsules et activités

- **Origine du code** : remonter d'une ligne au commit, puis aux PR, issues, reviews et checks liés si GitHub CLI est disponible.
- **Capsules de panne** : exporter commit de base, patchs, fichiers non suivis admissibles, commande en échec, sortie et versions en `.gatto`. Vérifier structure et empreintes avant restauration dans un worktree isolé, sans exécuter automatiquement les commandes incluses. Le filtrage ne couvre que les chemins sensibles connus et le contenu reconnu : vérifier avant partage.
- **Agents externes** : relier changements de fichiers/références et processus Agent connus travaillant dans le dépôt, avec force des indices. La présence d'un processus ne prouve pas sa responsabilité.

<a id="agent"></a>
### Des Agents au-delà des messages de commit

Codex CLI, Claude Code, Gemini CLI, OpenCode, DeepSeek Harness (dsh), Cursor Agent, GitHub Copilot CLI, Qwen Code et CLI personnalisées. Les instructions Git intégrées couvrent revue de l'index, brouillon de commit, conflits, branches, récupération d'historique, santé du dépôt et préparation de release ; les erreurs originales LFS, hooks, signature et synchronisation peuvent accompagner l'enquête.

Projet, traduction, recherche et installation ont des voies d'exécution distinctes. Prévisualiser une réécriture README avant application. Les réponses Issue/PR utilisent discussion et diff, restent éditables et ne sont envoyées qu'après confirmation. Conserver les CLI et modèles déjà configurés.

Une API compatible OpenAI ou DeepSeek peut aussi être configurée sans installer de CLI. Projet et traduction disposent de points d’accès et modèles distincts, listes de modèles, tests de capacités et réponses en streaming. Les clés sont dans le trousseau macOS. Les Agents API lisent le projet, exécutent des commandes et écrivent dans des chemins contrôlés ; la traduction n’a pas d’outil d’écriture.

<a id="project-tools"></a>
### Conserver le contexte d'un changement de tâche

Les **Contextes de travail** enregistrent fichiers indexés, non indexés et non suivis, branche, brouillons, fichier sélectionné, objectifs et liens. La restauration contrôle l'état du dépôt ; ouverture dans un worktree séparé possible. Fichiers ignorés exclus, ce n'est pas une sauvegarde indépendante.

| Outil | Usage |
| --- | --- |
| Recherche de code | Fichiers courants, révision ou changements historiques dans les dépôts gérés ; filtres dossier, langue, extension, aperçu et transmission à l'Agent. Recherche littérale avec limites de résultats. |
| Exécuter des commandes | Détecter les scripts, ajouter et épingler des commandes ; sortie, durée, état, arrêt, nouvel essai, services locaux. Exécution non interactive, arguments en tableau JSON. |
| Règles d’exclusion | Expliquer la provenance, prévisualiser `.gitignore` partagé ou `.git/info/exclude` local ; arrêter le suivi sans effacer les fichiers. |
| Identités de commit | Auteur et signature par dépôt ou dossier, provenance effective et contrôle avant commit ; distincts du compte GitHub. |

Accès par les outils du projet ou `⌘K`.

<a id="install-tools"></a>
### Installer, configurer et vérifier

Le catalogue lit GitHub Releases et distingue téléchargement et installation. DMG/ZIP suivent l'installation native, les paquets en ligne de commande passent à l'Agent. Phases, sortie et reprise restent visibles.

**99 outils et environnements d'exécution**, détection locale, sélection multiple et mises à niveau groupées. Files d'installation et de mise à niveau : trois tâches simultanées maximum ; écritures Homebrew sérialisées.

PATH requis, enregistrement des plugins, initialisation et migration précèdent la vérification de l'exécutable et de sa version. Téléchargement terminé ou déclaration de l'Agent ne remplacent pas ce contrôle. Permissions/configuration incomplètes restent à traiter ; connexion et autorisation système vous reviennent. La liste installée représente les installations GitGatto, pas toutes les apps du Mac.

<a id="git-github"></a>
## Git et GitHub au quotidien

- Index, commit, diff, graphe, blame, historique des fichiers et médias ; recherche combinée SHA, auteur, chemin, texte, date et référence.
- Branches, tags, remotes, stash, worktrees, comparaison et branche de récupération depuis reflog. Réordonner, fusionner, scinder, amender, cherry-pick, revert, reset ; contrôle des commits publiés avant réécriture et confirmation des opérations destructrices.
- Résoudre les conflits merge/rebase/stash, continuer, ignorer ou abandonner ; diagnostic LFS, hooks et outils.
- Fetch, pull et push groupés ; avance, retard, divergence, conflits et échecs par dépôt, reprise des échecs.
- Dépôts du compte, recherche de développeurs et en langage naturel, Star, Fork, clone, code, README, releases et pièces jointes.
- Boîte de réception pour reviews, mentions et checks échoués ; gestion des issues ; fichiers PR, marquage lu, commentaires de ligne, réponses et reviews.
- Actions : exécutions, logs, relance, annulation et artefacts. Rafraîchir une page ne déclenche pas d'écriture distante.

<a id="reading"></a>
## Lecture et traduction

Afficher Markdown, images relatives, sources, SVG et médias. Détection de langue, configuration de traduction séparée, cache lié au texte source, chemin et langue cible. Une source modifiée invalide sa traduction ; texte trop court ou déjà dans la bonne langue peut rester inchangé. Aucun commit README automatique.

<a id="appearance"></a>
## Thèmes et interface

Six thèmes : Brume légère, Verre dépoli doux, Console, Émeraude, Folio, Scène lumineuse, avec dispositions, panneaux, barre latérale et contrôles différents. Scène lumineuse sépare les couleurs claires/sombres du fond, des panneaux, textes, boutons et états ; préréglages Corail, Littoral, Forêt, Crépuscule.

Sections latérales repliables et défilantes, zones redimensionnables, 11 langues sans redémarrage. Mode d'emploi dans l'aide intégrée.

<a id="start"></a>
## Installation et démarrage

Télécharger le DMG depuis [Releases](https://github.com/Lincb522/GitGatto/releases/latest), glisser dans Applications. macOS 14+, Apple Silicon/Intel. [Changelog](CHANGELOG.md) et Releases décrivent les versions publiées ; cette page décrit le dépôt actuel.

| Usage | Prérequis |
| --- | --- |
| Git local et synchronisation distante | Git et authentification Git / SSH correspondante |
| GitHub, PR, Issue, Actions | [GitHub CLI](https://cli.github.com/) connectée |
| Agent, traduction, installation Agent | CLI configurée ou API compatible OpenAI / DeepSeek, avec modèle et droits adaptés à la tâche |
| Détection et mises à jour Homebrew | Homebrew |

Ouvrir un dépôt ou lancer une recherche manuelle et choisir les ajouts, sans importation automatique du disque entier. GitHub et Agents se règlent dans les paramètres. Mises à jour via GitHub Releases et Appcast.

<a id="data"></a>
## Données et permissions

Listes, réglages, objectifs, enquêtes, conversations, traductions, téléchargements et restaurations sont locaux ; le dossier de sauvegarde peut migrer. Git, SSH et les CLI utilisent leurs sources d'authentification habituelles.

Local ne signifie pas entièrement hors ligne : GitHub est contacté, Agents et traduction passent le contexte nécessaire à la CLI ou à l’API choisie. La suite dépend de l'outil et du service de modèle. Vérifier les envois et ne pas mettre d'identifiants dans commandes, brouillons ou capsules. Les changements système restent soumis aux autorisations macOS.

<a id="docs"></a>
## Plans, architecture et historique

[Feuille de route](docs/ROADMAP.md) · [Architecture](docs/ARCHITECTURE.md) · [Versions](CHANGELOG.md)

![Feuille de route GitGatto](docs/media/roadmap.svg)

![Architecture GitGatto](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

La feuille de route suit le code et les versions ; les pointillés sont des projets. Le graphique du 2026-09-12 UTC cumule les dates des Stargazers actuels, sans les étoiles retirées. Cliquer ouvre le suivi en ligne.

<a id="development"></a>
## Exécuter les sources

macOS 14+, Swift 6.1+ ; configuration Xcode dans `project.yml`.

```sh
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test --no-parallel
swift run GitGatto
```

Ou ouvrir `GitGatto.xcodeproj`, scheme `GitGatto`. Après modification structurelle, régénérer avec XcodeGen et `./scripts/generate-xcodeproj.sh`, sans éditer le projet à la main. SwiftUI, AppKit, WebKit, AVKit, Alamofire et Sparkle ; versions dans `Package.resolved`.

<a id="credits"></a>
## Contribution et licence

[Contribuer](CONTRIBUTING.md) · [Sécurité](SECURITY.md). Merci à [GitHub CLI](https://github.com/cli/cli), [Sparkle](https://github.com/sparkle-project/Sparkle), [Alamofire](https://github.com/Alamofire), [Reicon](https://github.com/Lincb522/reicon) et aux auteurs d'icônes et d'animations. Sources : [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Développé par **ZIJIU522**, sous [MIT License](LICENSE).
