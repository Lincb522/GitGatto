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
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="Última versión" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon e Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="Licencia MIT" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center"><a href="https://gatto.zijiu522.cn">Sitio web</a> · <a href="https://github.com/Lincb522/GitGatto/releases/latest">Descargar</a> · <a href="CHANGELOG.md">Historial de cambios</a> · <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a></p>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/media/github-project.png" alt="Proyecto de GitHub"><br><sub><b>Proyecto de GitHub</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/workspace.png" alt="Árbol de trabajo y diff"><br><sub><b>Árbol de trabajo y diff</b></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="docs/media/recovery-center.png" alt="Centro de recuperación"><br><sub><b>Centro de recuperación</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/file-time-machine.png" alt="Máquina del tiempo de archivos"><br><sub><b>Máquina del tiempo de archivos</b></sub></td>
  </tr>
</table>

Las capturas muestran la interfaz con datos de demostración. Los nombres y recuentos de proyectos no son métricas de uso.

GitGatto es un cliente nativo de Git y GitHub para macOS, compatible con Apple Silicon e Intel. Incluye copias de código sin commit, registros de Agents externos, objetivos de entrega, investigación de regresiones e instalación de herramientas de desarrollo.

<a id="why"></a>
## Por qué desarrollamos GitGatto

Después de escribir código quedan cambios mezclados, regresiones, CI, revisiones y publicaciones. Cambiar de tarea también puede hacer que perdamos de vista borradores y archivos sin commit.

Con Agents hay que comprobar qué cambiaron y por qué, qué pruebas dejó un fallo y si «terminado» significa que funciona. GitGatto aborda esas tareas y su recuperación, no solo añade botones a Git. Conserva Git del sistema y las CLI existentes, con acceso a cambios, pruebas y puntos de restauración.

[Recuperación](#recovery) · [Barra de menús](#monitoring) · [Objetivos](#goals) · [Separar commits](#intent) · [Regresiones](#regression) · [Herramientas](#project-tools) · [Instalación](#install-tools)

<a id="features"></a>
## Funciones destacadas

<a id="recovery"></a>
### Guardar cambios sin commit y observar herramientas externas

Los repositorios locales añadidos guardan un Git bundle y archivos sin commit. Las copias programadas o por cambios importantes omiten contenido sin cambios; también hay puntos manuales. Se conservan como máximo tres generaciones por repositorio.

Crear un punto antes de las escrituras del Agent. La protección observa borrados, pérdida de cambios, retrocesos de referencias y repositorios inaccesibles tras cambios externos, con motivos y rutas. Inspeccionar, comparar o exportar archivos, restaurar en otro directorio y migrar copias al cambiar su ubicación.

Ante un corte eléctrico se usa el último punto completo. Contenido y manifiesto se sincronizan antes del marcador final y de rotar copias antiguas. El siguiente inicio procesa escrituras interrumpidas. No se garantiza recuperar cambios posteriores, contenido sin guardar del editor ni archivos excluidos. La protección no bloquea cada comando de otras aplicaciones.

<a id="monitoring"></a>
### Consultar repositorios desde la barra de menús

Elegir todos los repositorios o uno, sin depender de la ventana: cambios, upstream, copias, Actions, objetivos y actividad diaria. La vista reducida incluye alcance, número de cambios y avisos; el panel se desplaza y sigue el tema. La actividad cuenta commits y cambios detectados, no horas.

Al activar la supervisión después de salir, un asistente independiente continúa la monitorización, las copias programadas o por grandes cambios y la protección según los ajustes. Al reabrir devuelve las tareas sin escaneos duplicados. Está desactivado por defecto y puede requerir aprobación de macOS.

Interruptor general, canales, visibilidad e intervalos se configuran por separado. Ocultar el icono no detiene las copias activas; desactivar el motor o la protección sí detiene esas tareas.

<a id="goals"></a>
### Retomar un objetivo de entrega

Elegir Commit y Push, Crear PR, Publicar versión o Personalizado; también iniciar desde cambios, Issues, PR o checks fallidos. Se prioriza el progreso actual y se despliegan los detalles y el historial cuando se necesitan.

Según el flujo se comprueban índice, commit, Push, PR, Review, Actions, artefactos, Release, DMG, Appcast y versión instalada. Las condiciones propuestas por el Agent requieren aprobación. Tras una interrupción se consulta el estado real, no se toma su texto como prueba de éxito. Fusionar, publicar etiquetas e instalar conservan confirmaciones independientes.

<a id="intent"></a>
### Dividir cambios mezclados en commits

Agrupar archivos o hunks de Diff con mensajes propios, con ayuda opcional de un Agent. Comprobar omisiones, duplicados y cambios del repositorio; crear un punto de restauración y hacer commits en orden.

Cada commit ejecuta una comprobación de diff o el comando de validación elegido. Ante un fallo se intenta recuperar HEAD e índice originales, sin garantizarlo en todas las circunstancias; el punto de restauración sigue disponible.

<a id="regression"></a>
### Investigar regresiones en un worktree aislado

`git bisect` no cambia el directorio de trabajo actual. Validación automática mediante comando o manual como correcto, defectuoso u omitido. Guarda candidatos, veredictos, códigos de salida, duración y salida.

Entregar pruebas a un Agent para corregir, volver a validar y preparar una PR. El comando debe detectar el fallo real; demasiados commits omitidos pueden dejar varios candidatos.

<a id="evidence"></a>
### Procedencia del código, cápsulas y actividad

- **Procedencia:** de una línea al commit y, con GitHub CLI, a PR, issues, reviews y checks relacionados.
- **Cápsulas de fallo:** exportar commit base, parches, archivos no rastreados permitidos, comando fallido, salida y versiones en `.gatto`. Validar estructura y hashes antes de restaurar en un worktree separado; los comandos incluidos no se ejecutan solos. Solo se filtran rutas sensibles conocidas y contenido reconocido: revisar antes de compartir.
- **Agents externos:** relacionar cambios de archivos y referencias con procesos Agent conocidos que trabajaban en el repositorio, mostrando fuerza de la evidencia. Coincidencia temporal no prueba autoría.

<a id="agent"></a>
### Agents para algo más que mensajes de commit

Codex CLI, Claude Code, Gemini CLI, OpenCode, DeepSeek Harness (dsh), Cursor Agent, GitHub Copilot CLI, Qwen Code y CLI personalizadas. Guías Git integradas para revisión del índice, borradores, conflictos, ramas, recuperación de historial, salud y publicación; pueden acompañarse de errores originales de LFS, hooks, firmas o sincronización.

Proyecto, traducción, búsqueda e instalación tienen vías separadas. Ver la reescritura del README antes de aplicarla. Las respuestas Issue/PR se basan en discusión y diff, son editables y se envían tras confirmar. Se mantienen las CLI y modelos configurados.

También admite una API compatible con OpenAI o DeepSeek sin instalar una CLI para ese modo. Proyecto y traducción tienen endpoints y modelos separados, lista de modelos, comprobaciones y respuestas en streaming. Las claves se guardan en el llavero de macOS. El Agent API lee proyectos, ejecuta comandos y escribe en rutas controladas; la traducción no recibe herramientas de escritura.

<a id="project-tools"></a>
### Guardar el contexto al cambiar de tarea

Los **Contextos de trabajo** guardan archivos preparados, no preparados y no rastreados, rama, borradores, archivo seleccionado, objetivos y enlaces. La restauración comprueba el estado; también se puede abrir un worktree aparte. Excluye archivos ignorados y no sustituye una copia independiente.

| Herramienta | Uso |
| --- | --- |
| Buscar código | Archivos actuales, revisión o cambios históricos entre repositorios gestionados; filtrar directorio, lenguaje o extensión y pasar pruebas al Agent. Búsqueda literal con resultados limitados. |
| Ejecutar comandos | Detectar scripts, añadir y fijar comandos; salida en vivo, duración, estado, detener, reintentar y abrir servicios locales. No interactivos; argumentos en arrays JSON. |
| Reglas de exclusión | Explicar origen y previsualizar `.gitignore` compartido o `.git/info/exclude` local; dejar de rastrear conservando los archivos. |
| Identidades de commit | Autor y firma por repositorio o directorio, origen efectivo y comprobación antes del commit. Separadas del inicio de sesión GitHub. |

Acceso desde herramientas del proyecto o `⌘K`.

<a id="install-tools"></a>
### Instalar, configurar y comprobar

El catálogo obtiene GitHub Releases y diferencia descarga e instalación. DMG/ZIP usan instalación nativa; los paquetes de línea de comandos van al Agent. Fases, salida y reintentos son visibles.

**99 herramientas y runtimes**, detección local, selección múltiple y actualizaciones por lotes. Colas de instalación y actualización con hasta tres tareas simultáneas; escrituras Homebrew serializadas.

PATH necesario, registro de plugins, inicialización y migración preceden a la comprobación del ejecutable y su versión. Una descarga o mensaje del Agent no sustituye esa validación. Permisos o configuración pendientes permanecen visibles; acceso a cuentas y autorización del sistema requieren al usuario. La lista instalada refleja instalaciones de GitGatto, no todas las apps del Mac.

<a id="git-github"></a>
## Git y GitHub habituales

- Índice, commit, diff, grafo, blame, historial de archivos y medios; búsqueda combinada por SHA, autor, ruta, texto, fecha y referencia.
- Ramas, tags, remotos, stash, worktrees, comparación y ramas de recuperación desde reflog. Reordenar, squash, dividir, amend, cherry-pick, revert y reset; comprobar commits publicados antes de reescribir y confirmar operaciones destructivas.
- Editar conflictos merge/rebase/stash, continuar, omitir o abortar; diagnosticar LFS, hooks y herramientas.
- Fetch, pull y push de varios repositorios; resultados separados de avance, retraso, divergencia, conflicto y error, con reintentos fallidos.
- Repositorios de cuenta, búsqueda de desarrolladores y lenguaje natural, Star, Fork, clone, código, README, releases y adjuntos.
- Bandeja de reviews, menciones y checks fallidos; creación y gestión de issues; archivos PR, marcas de visto, comentarios en línea, respuestas y reviews.
- Actions: ejecuciones, logs, repetir, cancelar y artefactos. Actualizar la página no produce escrituras remotas.

<a id="reading"></a>
## Lectura y traducción

Markdown, imágenes relativas, código, SVG y medios dentro de la app. Detección de idioma y configuración de traducción independiente; caché según origen, ruta e idioma objetivo, invalidada si cambia el original. Texto corto o ya traducido al idioma objetivo puede permanecer igual. No hace commit automático del README.

<a id="appearance"></a>
## Temas e interfaz

Seis temas: Niebla ligera, Vidrio esmerilado suave, Consola, Esmeralda, Folio, Escena luminosa, con cambios de distribución, paneles, barra lateral y controles. Escena luminosa permite colores claros/oscuros independientes para fondo, panel, texto, botones y estados; preajustes Coral, Costa, Bosque, Ocaso.

Secciones plegables y desplazables, áreas ajustables y 11 idiomas sin reiniciar. Instrucciones en la ayuda integrada.

<a id="start"></a>
## Instalación e inicio

Descargar DMG de [Releases](https://github.com/Lincb522/GitGatto/releases/latest) y arrastrar a Aplicaciones. macOS 14+, Apple Silicon/Intel. [Changelog](CHANGELOG.md) y Releases indican lo publicado; este README describe el repositorio actual.

| Uso | Requisito |
| --- | --- |
| Git local y sincronización normal | Git y autenticación Git / SSH del remoto |
| GitHub, PR, Issue, Actions | [GitHub CLI](https://cli.github.com/) con sesión iniciada |
| Agent, traducción, instalación Agent | CLI configurada o API compatible con OpenAI / DeepSeek, con modelo y permisos para la tarea |
| Detección y actualización Homebrew | Homebrew |

Abrir un repositorio o escanear manualmente y seleccionar, sin importación automática de todo el disco. GitHub y Agents se configuran en Ajustes; actualizaciones mediante Releases y Appcast.

<a id="data"></a>
## Datos y permisos

Listas, ajustes, objetivos, investigaciones, conversaciones, traducciones, descargas y restauraciones son locales; el directorio de copias puede migrar. Git, SSH y las CLI conservan sus fuentes de credenciales.

Local no significa totalmente offline: se contacta GitHub y se entrega contexto necesario a la CLI o API del Agent o traducción. El tratamiento posterior depende de herramienta y servicio del modelo. Revisar los envíos y no incluir credenciales en comandos, borradores o cápsulas. Los cambios en directorios del sistema requieren autorización macOS.

<a id="docs"></a>
## Planes, arquitectura e historial

[Hoja de ruta](docs/ROADMAP.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Versiones](CHANGELOG.md)

![Hoja de ruta GitGatto](docs/media/roadmap.svg)

![Arquitectura GitGatto](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

La hoja de ruta sigue el código y las versiones; los trazos discontinuos son planes. El gráfico del 2026-09-12 UTC acumula las fechas de los Stargazers actuales, sin estrellas retiradas. Pulsa para ver el registro en línea.

<a id="development"></a>
## Ejecutar desde código

macOS 14+, Swift 6.1+; configuración Xcode en `project.yml`.

```sh
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test --no-parallel
swift run GitGatto
```

También se puede abrir `GitGatto.xcodeproj` con el scheme `GitGatto`. Tras cambios estructurales, regenerar mediante XcodeGen y `./scripts/generate-xcodeproj.sh`, sin edición manual del proyecto. SwiftUI, AppKit, WebKit, AVKit, Alamofire y Sparkle; versiones en `Package.resolved`.

<a id="credits"></a>
## Contribución y licencia

[Contribuir](CONTRIBUTING.md) · [Seguridad](SECURITY.md). Gracias a [GitHub CLI](https://github.com/cli/cli), [Sparkle](https://github.com/sparkle-project/Sparkle), [Alamofire](https://github.com/Alamofire), [Reicon](https://github.com/Lincb522/reicon) y autores de iconos y animaciones. Fuentes: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Desarrollado por **ZIJIU522**, bajo [MIT License](LICENSE).
