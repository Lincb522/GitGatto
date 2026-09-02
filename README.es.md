<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">Un cliente Git nativo dirigido por Agents.</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a>
</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="Última versión" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon e Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="Licencia MIT" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center"><a href="https://gatto.zijiu522.cn">Sitio web</a> · <a href="https://github.com/Lincb522/GitGatto/releases/latest">Descargar</a> · <a href="CHANGELOG.md">Historial de cambios</a> · <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a></p>

![Área de trabajo de GitGatto](docs/media/workspace.png)

GitGatto es un cliente nativo de Git y GitHub para macOS. El estado de los repositorios procede del Git del sistema, las operaciones remotas usan GitHub CLI y los Agents trabajan con las CLI ya instaladas y autenticadas en el Mac. GitGatto reúne sus estados, pasos y resultados en una sola vista de proyecto.

## Por qué existe GitGatto

Una entrega completa suele repartirse entre el terminal, el editor, GitHub, Actions y la página de versiones. Si un paso falla, hay que volver a comprobar la rama, los archivos preparados, los registros y los artefactos. Al añadir un Agent también hay que verificar su directorio de trabajo, sus permisos y si su contexto corresponde al repositorio actual.

GitGatto nació de estos problemas cotidianos. Conserva el Git real y las herramientas existentes, y conecta las operaciones del repositorio, la colaboración en GitHub, el trabajo de los Agents y las pruebas de cada fallo en un proceso que se puede revisar, pausar y reanudar.

## Flujos propios

### Objetivos de proyecto

«Entregar cambios actuales», «Entrega en GitHub» y «Versión completa» comprueban, en orden de dependencia, el área de preparación, los commits, Push, Pull Request, Reviews, Actions, artefactos, Release, DMG, Appcast y la versión instalada. También se puede describir el resultado en lenguaje natural y revisar sus condiciones antes de ejecutarlo.

Cada paso lee el estado real de Git, GitHub o del Mac. Los pasos terminados se conservan tras una interrupción y un fallo de Actions puede entregarse a un Agent junto con sus pruebas. Fusionar, publicar una etiqueta e instalar siguen requiriendo confirmaciones separadas.

### Investigación de regresiones

Ejecuta `git bisect` en un worktree aislado sin cambiar el área de trabajo actual. El modo automático lanza el comando de verificación elegido; el manual marca cada candidato como correcto, defectuoso u omitido. Se guardan commits candidatos, códigos de salida, duración y salida. Tras localizar el primer commit defectuoso, un Agent puede preparar la corrección, repetir la verificación y crear una Pull Request.

### Recuperación de repositorios

El centro de recuperación supervisa los repositorios locales añadidos a GitGatto. Guarda el trabajo sin commit de forma periódica, crea un punto cuando se alcanza el umbral de archivos o líneas y también permite copias manuales. El contenido sin cambios no vuelve a escribirse.

Cada punto contiene un Git bundle y copias de los archivos sin commit. Se conservan como máximo tres puntos rotativos por repositorio. Se puede consultar el espacio, abrir carpetas, borrar un punto o todas las copias de un repositorio y restaurar un punto como una nueva copia del repositorio. Al cambiar la ubicación, los datos existentes se migran y verifican antes de usar el nuevo destino.

### Agents especializados en Git

GitGatto admite Codex CLI, Claude Code, Gemini CLI, OpenCode y plantillas de CLI personalizadas. Las tareas del repositorio, la traducción y la instalación de software usan canales de ejecución distintos, por lo que una tarea larga no bloquea la traducción de documentos.

Un Agent puede usar la salida de error completa para tratar problemas de Git, Git LFS, hooks, firma, ramas, sincronización, conflictos, Pull Requests y Actions. Si no hay nada preparado, la redacción del commit puede preparar primero los cambios y después hacer commit o commit y Push. Una reescritura del README se renderiza completa antes de que «Aplicar commit» confirme solo ese documento.

## Git y GitHub

- Gestionar árbol de trabajo, área de preparación, commits, Pull, Push, ramas, stashes y worktrees.
- Consultar diffs por línea, grafo de commits, Blame, historial de archivos e imágenes, SVG o vídeo de revisiones anteriores.
- Editar resultados de conflictos de merge, rebase y stash, y después continuar, omitir o cancelar.
- Cargar repositorios accesibles para la cuenta de GitHub actual; buscar repositorios y desarrolladores con coincidencia aproximada, lenguaje natural y más páginas.
- Leer código, README, Pull Requests, Actions, Releases y archivos publicados dentro de la aplicación.
- Revisar archivos de una Pull Request, marcarlos como vistos, comentar líneas, responder, enviar Reviews, volver a ejecutar o cancelar Actions y descargar artefactos.
- Dar Star, hacer Fork y clonar. El escaneo local se inicia manualmente y permite elegir qué repositorios añadir en lugar de importar todo el disco.

## Documentos, traducción y vistas previas

- Renderizar Markdown, imágenes relativas y enlaces internos del repositorio dentro de GitGatto.
- Detectar el idioma y traducir por un canal Agent separado; las traducciones se guardan localmente por versión del original.
- Previsualizar código, imágenes, fuente SVG y archivos multimedia desde el área de trabajo y los historiales de commits y archivos.
- El Agent de README reconstruye el documento a partir de archivos, dependencias y recursos existentes, en lugar de limitarse a cambiar palabras.

## Catálogo de aplicaciones y herramientas de desarrollo

- Buscar aplicaciones instalables en GitHub Releases con su icono, descripción, capturas, versión y paquetes reales. DMG y ZIP usan el instalador local; otros formatos pasan a un Agent.
- Detectar versiones instaladas y actualizaciones para 99 entornos, herramientas de compilación, contenedores, herramientas de nube, bases de datos y utilidades CLI.
- Ejecutar instalaciones y actualizaciones en tres vías paralelas con selección múltiple y actualización por lotes. Los cambios de Homebrew usan una cola serie independiente para evitar escrituras simultáneas en Cellar.
- Tras instalar, el Agent completa PATH por usuario, registro de componentes, inicialización y migración de configuración, y vuelve a comprobar el ejecutable y la versión.
- Conservar el progreso por etapas, la salida original y explicaciones localizadas de errores conocidos durante descarga, instalación, configuración y verificación.

## Documentos del proyecto

- [Hoja de ruta](docs/ROADMAP.md): etapas implementadas, trabajo previsto y límites.
- [Arquitectura](docs/ARCHITECTURE.md): propiedad del estado, límites de servicios y flujos principales.
- [Curva de versiones](docs/UPDATE_HISTORY.md): historial generado a partir de las fechas del CHANGELOG.

![GitGatto roadmap](docs/media/roadmap.svg)

![GitGatto architecture](docs/media/architecture-overview.svg)

![Curva de versiones de GitGatto](docs/media/update-curve.svg)

## Instalación

Descarga el DMG desde [Releases](https://github.com/Lincb522/GitGatto/releases/latest) y arrastra GitGatto a Aplicaciones. Las versiones son binarios universales para Apple Silicon e Intel y requieren macOS 14 o posterior.

| Función | Requisito |
| --- | --- |
| Repositorios locales | Git |
| Repositorios GitHub, PR, Actions y operaciones remotas | [GitHub CLI](https://cli.github.com/) autenticada |
| Agents | Al menos una CLI compatible instalada y autenticada |
| Comprobación de Homebrew | Homebrew |

Las actualizaciones integradas, notas de versión e instaladores proceden de los GitHub Releases de este repositorio.

## Datos locales y permisos

- Ajustes, lista de repositorios, objetivos, investigaciones de regresión, conversaciones y registros de Agents, descargas y traducciones permanecen en el Mac.
- Al activar la protección, los Git bundles y las copias de archivos sin commit se guardan en Application Support o en la ubicación elegida. Cada repositorio conserva como máximo tres copias, eliminables desde el centro de recuperación.
- Git, SSH, GitHub CLI y las CLI de Agent siguen usando sus propios almacenes de credenciales. GitGatto no guarda tokens, contraseñas ni claves privadas.
- Pull, Push, Fork, comentarios, Reviews, Actions, instalaciones de aplicaciones y cambios de herramientas solo se ejecutan tras una acción explícita en la aplicación.

## Desarrollo

Se necesita macOS 14 o posterior y la cadena de herramientas Swift declarada por el proyecto.

```bash
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
open GitGatto.xcodeproj
```

El código usa Swift 6, SwiftUI, AppKit, WebKit y AVKit; Alamofire 5.12 para red y Sparkle 2.9.6 para actualizaciones. Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para contribuir y [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) para los límites del sistema.

## Agradecimientos

- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Alamofire](https://github.com/Alamofire/Alamofire)
- [SwiftUI-Animations](https://github.com/Shubham0812/SwiftUI-Animations)
- [GitHub CLI](https://github.com/cli/cli)
- [Simple Icons](https://github.com/simple-icons/simple-icons), [VSCode Icons](https://github.com/vscode-icons/vscode-icons), [Devicon](https://github.com/devicons/devicon) y [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)

Las versiones y licencias exactas figuran en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Informa de problemas de seguridad por el canal indicado en [SECURITY.md](SECURITY.md).

## Licencia

GitGatto está desarrollado por **ZIJIU522** y se publica bajo la [licencia MIT](LICENSE).
