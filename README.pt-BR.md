<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">Um cliente Git nativo, orientado por Agents.</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a>
</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="Versão mais recente" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon e Intel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="Licença MIT" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center"><a href="https://gatto.zijiu522.cn">Site</a> · <a href="https://github.com/Lincb522/GitGatto/releases/latest">Baixar</a> · <a href="CHANGELOG.md">Histórico</a> · <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a></p>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/media/github-project.png" alt="Projeto no GitHub"><br><sub><b>Projeto no GitHub</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/workspace.png" alt="Árvore de trabalho e diff"><br><sub><b>Árvore de trabalho e diff</b></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="docs/media/recovery-center.png" alt="Central de recuperação"><br><sub><b>Central de recuperação</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/file-time-machine.png" alt="Arquivo Máquina do Tempo"><br><sub><b>Arquivo Máquina do Tempo</b></sub></td>
  </tr>
</table>

GitGatto é um cliente nativo de Git e GitHub para macOS. O estado dos repositórios vem do Git do sistema, as operações remotas usam o GitHub CLI e os Agents usam CLIs já instaladas e autenticadas no Mac. O aplicativo reúne seus estados, etapas e resultados em uma única visão do projeto.

## Por que o GitGatto foi criado

Uma entrega completa costuma passar pelo terminal, editor, GitHub, Actions e página de versão. Se uma etapa falha, é preciso conferir novamente a branch, os arquivos preparados, os logs e os artefatos. Com um Agent, também é necessário confirmar o diretório de trabalho, as permissões e se o contexto pertence ao repositório atual.

O GitGatto nasceu desses problemas do dia a dia. Ele mantém o Git real e as ferramentas existentes, e conecta operações do repositório, colaboração no GitHub, tarefas de Agent e evidências de falha em um processo que pode ser inspecionado, pausado e retomado.

## Fluxos próprios

### Objetivos de projeto

“Entregar alterações atuais”, “Entrega no GitHub” e “Versão completa” verificam, em ordem de dependência, staging, commits, Push, Pull Request, Reviews, Actions, artefatos, Release, DMG, Appcast e a versão instalada. Também é possível descrever o resultado em linguagem natural e revisar as condições geradas antes da execução.

Cada etapa lê o estado real do Git, GitHub ou Mac. Etapas concluídas permanecem após uma interrupção; uma falha de Actions pode ser enviada a um Agent junto com suas evidências. Merge, publicação de tag e instalação continuam exigindo confirmações separadas.

### Organização de mudanças e evidências

- A central de mudanças agrupa alterações por arquivo ou trecho de Diff e pode criar vários commits atômicos. Antes, confere a impressão do repositório e cria um ponto de recuperação; se um commit ou verificação falhar, restaura o HEAD e o limite de staging originais.
- A origem do código rastreia uma linha até o commit e, quando o GitHub CLI está disponível, acrescenta Pull Request, Issues, Reviews e Checks relacionados.
- Cápsulas de reprodução empacotam patch, arquivos não rastreados, commit base, comando com falha, saída e versões das ferramentas como `.gatto`. A importação valida o conteúdo e o restaura em um worktree isolado.
- O registro de atividades guarda mudanças em referências Git e estados de arquivos com processos Agent cujo diretório de trabalho estava dentro do repositório. A confiança da associação é exibida sem tratá-la como responsabilidade comprovada.

### Investigação de regressão

Executa `git bisect` em um worktree isolado sem trocar a área de trabalho atual. O modo automático roda um comando de verificação; o manual classifica cada candidato como bom, ruim ou ignorado. Commits candidatos, códigos de saída, duração e saída são salvos. Depois de localizar o primeiro commit com falha, um Agent pode preparar a correção, repetir a verificação e abrir um Pull Request.

### Recuperação de repositórios

A central de recuperação monitora os repositórios locais adicionados ao GitGatto. Salva trabalho sem commit em intervalos definidos, cria um ponto quando o limite de arquivos ou linhas é atingido e aceita backup manual. Conteúdo inalterado não é gravado novamente.

Cada ponto contém um Git bundle e cópias dos arquivos sem commit. São mantidos no máximo três pontos rotativos por repositório. É possível consultar o espaço usado, abrir pastas, apagar um ponto ou todos os backups de um repositório e restaurar um ponto como uma nova cópia do repositório. Ao mudar o local, os dados existentes são migrados e verificados antes da troca.

### Agents voltados para Git

GitGatto oferece suporte a Codex CLI, Claude Code, Gemini CLI, OpenCode e modelos de CLI personalizados. Operações do repositório, tradução e instalação de software usam canais separados, então uma tarefa longa não bloqueia a tradução de documentos.

Um Agent pode usar a saída completa de erros para tratar Git, Git LFS, hooks, assinatura, branches, sincronização, conflitos, Pull Requests e Actions. Se nada estiver em staging, a criação da mensagem pode preparar as alterações primeiro e então fazer commit ou commit e Push. A reescrita do README é renderizada por inteiro antes de “Aplicar commit” registrar apenas esse documento.

## Git e GitHub

- Gerenciar árvore de trabalho, staging, commits, Pull, Push, branches, stashes e worktrees.
- Ver diffs por linha, grafo de commits, Blame, histórico de arquivo e imagens, SVG ou vídeos de revisões anteriores.
- Editar resultados de conflitos de merge, rebase e stash, e depois continuar, ignorar ou abortar.
- Carregar repositórios acessíveis pela conta atual do GitHub e pesquisar repositórios e desenvolvedores com busca aproximada, linguagem natural e carregamento contínuo.
- Ler código, README, Pull Requests, Actions, Releases e anexos dentro do aplicativo.
- Revisar arquivos de Pull Request, marcar como vistos, comentar linhas, responder, enviar Reviews, executar novamente ou cancelar Actions e baixar artefatos.
- Dar Star, fazer Fork e clonar. A varredura local é iniciada manualmente e permite escolher o que adicionar, sem importar o disco inteiro.

## Documentos, tradução e visualização

- Renderizar Markdown, imagens relativas e links internos do repositório dentro do GitGatto.
- Detectar o idioma e traduzir por um canal Agent separado; traduções ficam salvas localmente por versão do texto original.
- Visualizar código, imagens, fonte SVG e mídia a partir da área de trabalho, histórico de commits e histórico de arquivos.
- O Agent de README reconstrói o documento usando arquivos, dependências e recursos existentes, em vez de apenas trocar palavras.

## Catálogo de aplicativos e ferramentas de desenvolvimento

- Encontrar aplicativos instaláveis no GitHub Releases com ícone, descrição, capturas, versão e pacotes reais. DMG e ZIP usam o instalador local; outros formatos são tratados por um Agent.
- Detectar versões instaladas e atualizações de 99 ambientes, ferramentas de build, contêineres, ferramentas de nuvem, bancos de dados e utilitários CLI.
- Executar instalações e atualizações em três vias paralelas, com seleção múltipla e atualização em lote. Alterações do Homebrew usam uma fila serial separada para evitar gravações simultâneas no Cellar.
- Após a instalação, o Agent conclui PATH do usuário, registro de componentes, inicialização e migração de configuração, e verifica novamente executável e versão.
- Manter progresso por etapas, saída original e explicações localizadas de erros conhecidos durante download, instalação, configuração e verificação.

## Documentos do projeto

- [Roteiro](docs/ROADMAP.md): etapas implementadas, trabalho planejado e limites.
- [Arquitetura](docs/ARCHITECTURE.md): propriedade de estado, limites de serviços e fluxos principais.
- [Star History](https://www.star-history.com/#Lincb522/GitGatto&Date): evolução das estrelas no GitHub.

![GitGatto roadmap](docs/media/roadmap.svg)

![GitGatto architecture](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

## Instalação

Baixe o DMG em [Releases](https://github.com/Lincb522/GitGatto/releases/latest) e arraste o GitGatto para Aplicativos. As versões são binários universais para Apple Silicon e Intel e exigem macOS 14 ou posterior.

| Recurso | Requisito |
| --- | --- |
| Repositórios locais | Git |
| Repositórios GitHub, PRs, Actions e operações remotas | [GitHub CLI](https://cli.github.com/) autenticado |
| Agents | Pelo menos uma CLI compatível instalada e autenticada |
| Verificação de atualizações do Homebrew | Homebrew |

Atualizações no aplicativo, notas de versão e instaladores vêm dos GitHub Releases deste repositório.

## Dados locais e permissões

- Configurações, lista de repositórios, objetivos, investigações de regressão, conversas e registros de Agents, downloads e traduções permanecem no Mac.
- Com a proteção ativada, Git bundles e cópias de arquivos sem commit são salvos no Application Support ou no local escolhido. Cada repositório mantém no máximo três cópias, removíveis pela central de recuperação.
- Git, SSH, GitHub CLI e CLIs de Agent continuam usando seus próprios armazenamentos de credenciais. GitGatto não guarda tokens, senhas nem chaves privadas.
- Pull, Push, Fork, comentários, Reviews, Actions, instalação de aplicativos e alterações de ferramentas só são executados após uma ação explícita no aplicativo.

## Desenvolvimento

Requer macOS 14 ou posterior e o toolchain Swift declarado pelo projeto.

```bash
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
open GitGatto.xcodeproj
```

O código usa Swift 6, SwiftUI, AppKit, WebKit e AVKit; Alamofire 5.12 para rede e Sparkle 2.9.6 para atualizações. Consulte [CONTRIBUTING.md](CONTRIBUTING.md) para contribuir e [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) para os limites do sistema.

## Agradecimentos

- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Alamofire](https://github.com/Alamofire/Alamofire)
- [SwiftUI-Animations](https://github.com/Shubham0812/SwiftUI-Animations)
- [GitHub CLI](https://github.com/cli/cli)
- [Simple Icons](https://github.com/simple-icons/simple-icons), [VSCode Icons](https://github.com/vscode-icons/vscode-icons), [Devicon](https://github.com/devicons/devicon) e [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)

Versões e licenças exatas estão em [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Relate questões de segurança pelo canal descrito em [SECURITY.md](SECURITY.md).

## Licença

GitGatto é desenvolvido por **ZIJIU522** e publicado sob a [licença MIT](LICENSE).
