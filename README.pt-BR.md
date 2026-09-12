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

As capturas mostram a interface com dados de demonstração. Nomes e contagens de projetos não são métricas de uso.

GitGatto é um cliente nativo Git e GitHub para macOS, compatível com Apple Silicon e Intel. Inclui backup de código sem commit, registros de Agents externos, metas de entrega, investigação de regressões e configuração de ferramentas de desenvolvimento.

<a id="why"></a>
## Por que desenvolvemos o GitGatto

Depois do código ainda vêm alterações misturadas, regressões, CI, revisão de PRs e releases. Trocar de tarefa também pode fazer perder de vista rascunhos e arquivos sem commit.

Com Agents surgem perguntas: o que mudou e por quê, quais evidências restaram de uma falha e se o resultado anunciado funciona. O GitGatto cuida dessas tarefas e de sua retomada, não apenas coloca botões sobre o Git. Mantém o Git do sistema e as CLIs existentes, com acesso a alterações, evidências e pontos de recuperação.

[Recuperação](#recovery) · [Barra de menus](#monitoring) · [Metas](#goals) · [Separar commits](#intent) · [Regressões](#regression) · [Ferramentas](#project-tools) · [Instalação](#install-tools)

<a id="features"></a>
## Recursos de destaque

<a id="recovery"></a>
### Proteger trabalho sem commit e observar alterações externas

Repositórios locais adicionados guardam Git bundles e arquivos sem commit. Backups agendados ou de grandes mudanças ignoram conteúdo inalterado; pontos manuais também estão disponíveis. São mantidas até três gerações por repositório.

Criar um ponto antes da escrita do Agent. A proteção observa exclusões, perda de alterações, recuo de referências e repositórios indisponíveis após mudanças externas, mostrando motivos e caminhos. Inspecionar, comparar e exportar arquivos, restaurar em outro diretório e migrar os backups ao trocar a pasta.

Após queda de energia, a recuperação usa o último ponto completo. Conteúdo e manifesto são sincronizados antes do marcador de conclusão e da rotação de cópias antigas. Escritas interrompidas são tratadas na próxima inicialização. Alterações posteriores, conteúdo não salvo no editor e arquivos excluídos pelas regras não têm recuperação garantida. A proteção não bloqueia todo comando de outros aplicativos.

<a id="monitoring"></a>
### Consultar repositórios pela barra de menus

Escolher todos ou um repositório sem depender da janela: alterações, upstream, backups, Actions, metas e atividade diária. A indicação recolhida inclui escopo, contagem e avisos; o painel tem rolagem e segue o tema. A atividade conta commits e mudanças detectadas, não horas trabalhadas.

Ativar a continuidade após sair permite que um assistente independente mantenha monitoramento, backups agendados ou de grandes alterações e proteção conforme os ajustes. Ao reabrir, ele devolve as tarefas sem duplicar varreduras. Desativado por padrão; pode exigir aprovação do macOS.

Chave geral, canais, visibilidade e intervalos são separados. Ocultar o ícone não para backups ativos; desligar o mecanismo ou a proteção interrompe as tarefas correspondentes.

<a id="goals"></a>
### Retomar uma meta de entrega

Escolher Commit e Push, Criar PR, Publicar versão ou Personalizado; também começar por mudanças, Issues, PRs ou checks com falha. O progresso atual fica em destaque; detalhes e histórico podem ser expandidos.

Conforme o fluxo, verificar índice, commit, Push, PR, Review, Actions, artefatos, Release, DMG, Appcast e versão instalada. Condições propostas pelo Agent exigem aprovação. Após interrupção, o estado real é consultado de novo; texto do Agent não comprova sucesso. Merge, publicação de tags e instalação têm confirmações próprias.

<a id="intent"></a>
### Separar alterações misturadas em commits

Agrupar arquivos ou hunks de Diff com mensagens individuais, com ajuda opcional do Agent. Verificar omissões, duplicações e mudanças do repositório, criar recuperação e commitar em ordem.

Cada commit passa por checagem de diff ou comando de verificação escolhido. Falhas levam a uma tentativa de restaurar HEAD e índice originais, sem garantia em toda situação; o ponto de recuperação continua disponível.

<a id="regression"></a>
### Investigar regressões em worktree isolada

Executar `git bisect` sem trocar o diretório atual. Automaticamente por comando ou manualmente como correto, falho ou ignorado. Guardar candidatos, decisões, códigos de saída, duração e saída.

Enviar evidências ao Agent para correção, nova validação e preparação de PR. O comando deve identificar o problema; muitos commits ignorados podem deixar mais de um candidato.

<a id="evidence"></a>
### Origem do código, cápsulas e atividade

- **Origem:** seguir uma linha até o commit e, com GitHub CLI, PRs, issues, reviews e checks relacionados.
- **Cápsulas de falha:** exportar commit base, patches, arquivos não rastreados permitidos, comando falho, saída e versões em `.gatto`. Validar estrutura e hashes antes de restaurar em worktree isolada; comandos incluídos não rodam automaticamente. Apenas caminhos sensíveis conhecidos e conteúdo reconhecido são filtrados: conferir antes de compartilhar.
- **Agents externos:** relacionar alterações de arquivos/referências a processos Agent conhecidos trabalhando no repositório e mostrar força das evidências. Estar em execução não prova autoria.

<a id="agent"></a>
### Agents além das mensagens de commit

Codex CLI, Claude Code, Gemini CLI, OpenCode, DeepSeek Harness (dsh), Cursor Agent, GitHub Copilot CLI, Qwen Code e CLIs personalizadas. Orientações Git integradas para revisão do índice, rascunhos, conflitos, branches, recuperação de histórico, saúde e release; erros originais de LFS, hooks, assinatura e sincronização podem acompanhar a investigação.

Projeto, tradução, busca e instalação têm caminhos de execução separados. Pré-visualizar reescritas do README antes de aplicar. Respostas Issue/PR usam discussão e diff, permanecem editáveis e só são enviadas após confirmação. Manter CLIs e modelos já configurados.

Também aceita API compatível com OpenAI ou DeepSeek sem instalar CLI nesse modo. Projeto e tradução têm endpoints e modelos separados, lista de modelos, testes de capacidade e respostas em streaming. Chaves ficam no Acesso às Chaves do macOS. O Agent API lê projetos, executa comandos e escreve em caminhos controlados; tradução não recebe ferramentas de escrita.

<a id="project-tools"></a>
### Guardar o contexto ao trocar de tarefa

**Contextos de trabalho** guardam arquivos preparados, não preparados e não rastreados, branch, rascunhos, arquivo selecionado, metas e links. A restauração verifica o estado e pode abrir uma worktree separada. Arquivos ignorados ficam fora; não é backup independente.

| Ferramenta | Uso |
| --- | --- |
| Buscar código | Arquivos atuais, revisão ou mudanças históricas entre repositórios gerenciados, filtros de diretório, linguagem e extensão, prévia e evidências para o Agent. Busca literal, resultados limitados. |
| Executar comandos | Detectar scripts, adicionar e fixar comandos; saída ao vivo, tempo, estado, parar, repetir e abrir serviços locais. Não interativo, argumentos em array JSON. |
| Regras de exclusão | Explicar origem, pré-visualizar `.gitignore` compartilhado ou `.git/info/exclude` local; parar rastreamento mantendo arquivos. |
| Identidades de commit | Autor e assinatura por repositório/diretório, origem efetiva e verificação antes do commit; separado do login GitHub. |

Abrir pelas ferramentas do projeto ou `⌘K`.

<a id="install-tools"></a>
### Instalar, configurar e verificar

O catálogo usa GitHub Releases e separa download de instalação. DMG/ZIP usam instalação nativa; pacotes de terminal vão para o Agent. Fases, saída e novas tentativas ficam visíveis.

**99 ferramentas e runtimes**, detecção local, seleção múltipla e atualização em lote. Filas de instalação e atualização com até três tarefas simultâneas; escrita Homebrew serializada.

PATH necessário, registro de plugins, inicialização e migração precedem a verificação do executável e versão. Download ou relato do Agent não substituem validação. Permissões e configuração pendentes continuam acionáveis; login e autorização do sistema dependem do usuário. A lista instalada registra instalações GitGatto, não todos os apps do Mac.

<a id="git-github"></a>
## Git e GitHub no dia a dia

- Índice, commit, diff, grafo, blame, histórico de arquivos e mídias; busca combinada por SHA, autor, caminho, texto, data e referência.
- Branches, tags, remotos, stash, worktrees, comparação e branches de recuperação via reflog. Reordenar, squash, dividir, amend, cherry-pick, revert e reset; checar commits publicados antes de reescrever e confirmar ações destrutivas.
- Conflitos merge/rebase/stash, continuar, ignorar ou abortar; diagnóstico de LFS, hooks e ferramentas.
- Fetch, pull e push em vários repositórios; avanço, atraso, divergência, conflitos e falhas por item, com repetição dos que falharam.
- Repositórios da conta, busca de desenvolvedores e linguagem natural, Star, Fork, clone, código, README, releases e anexos.
- Caixa de entrada de reviews, menções e checks falhos; criar e gerenciar issues; arquivos PR, marcação de vistos, comentários de linha, respostas e reviews.
- Actions: execuções, logs, repetir, cancelar e baixar artefatos. Atualização de página não dispara escrita remota.

<a id="reading"></a>
## Leitura e tradução

Markdown, imagens relativas, código, SVG e mídia no app. Detecção de idioma e configuração separada de tradução; cache por origem, caminho e idioma alvo. Mudança na origem invalida tradução antiga. Texto curto ou já no idioma alvo pode ficar como está. Não há commit automático do README.

<a id="appearance"></a>
## Temas e interface

Seis temas: Névoa leve, Vidro fosco macio, Console, Esmeralda, Fólio, Palco luminoso, com mudanças de layout, painéis, barra lateral e controles. Palco luminoso separa cores claras/escuras de fundo, painéis, texto, botões e estados, com predefinições Coral, Litoral, Floresta, Crepúsculo.

Seções recolhíveis e roláveis, áreas ajustáveis e 11 idiomas sem reiniciar. Instruções na ajuda integrada.

<a id="start"></a>
## Instalar e começar

Baixar o DMG em [Releases](https://github.com/Lincb522/GitGatto/releases/latest) e arrastar para Aplicativos. macOS 14+, Apple Silicon/Intel. [Changelog](CHANGELOG.md) e Releases mostram versões publicadas; este README descreve o repositório atual.

| Uso | Requisito |
| --- | --- |
| Git local e sincronização comum | Git e autenticação Git / SSH do remoto |
| GitHub, PR, Issue, Actions | [GitHub CLI](https://cli.github.com/) autenticada |
| Agent, tradução, instalação Agent | CLI configurada ou API compatível com OpenAI / DeepSeek, com modelo e permissões para a tarefa |
| Detecção e atualização Homebrew | Homebrew |

Abrir repositório ou fazer busca manual e selecionar, sem importação automática do disco inteiro. Configurar GitHub e Agents nos ajustes; atualizações via GitHub Releases e Appcast.

<a id="data"></a>
## Dados e permissões

Listas, ajustes, metas, investigações, conversas, traduções, downloads e pontos de recuperação são locais; o diretório de backup pode migrar. Git, SSH e CLIs usam suas fontes de credenciais.

Local não significa totalmente offline: GitHub é acessado e Agents/tradução recebem o contexto necessário pela CLI ou API escolhida. O tratamento posterior depende da ferramenta e do serviço de modelo. Conferir envios e não colocar credenciais em comandos, rascunhos ou cápsulas. Mudanças em diretórios do sistema exigem autorização macOS.

<a id="docs"></a>
## Planos, arquitetura e histórico

[Roadmap](docs/ROADMAP.md) · [Arquitetura](docs/ARCHITECTURE.md) · [Versões](CHANGELOG.md)

![Roadmap GitGatto](docs/media/roadmap.svg)

![Arquitetura GitGatto](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

O roteiro acompanha o código e as versões; linhas tracejadas são planos. O gráfico de 2026-09-12 UTC acumula as datas dos Stargazers atuais, sem estrelas removidas. Clique para abrir o registro online.

<a id="development"></a>
## Executar pelo código

macOS 14+, Swift 6.1+; configuração Xcode em `project.yml`.

```sh
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test --no-parallel
swift run GitGatto
```

Ou abrir `GitGatto.xcodeproj` com scheme `GitGatto`. Mudanças de estrutura devem ser regeneradas com XcodeGen e `./scripts/generate-xcodeproj.sh`, não editadas no projeto gerado. SwiftUI, AppKit, WebKit, AVKit, Alamofire e Sparkle; versões em `Package.resolved`.

<a id="credits"></a>
## Contribuição e licença

[Contribuir](CONTRIBUTING.md) · [Segurança](SECURITY.md). Agradecemos [GitHub CLI](https://github.com/cli/cli), [Sparkle](https://github.com/sparkle-project/Sparkle), [Alamofire](https://github.com/Alamofire), [Reicon](https://github.com/Lincb522/reicon) e autores de ícones/animações. Fontes: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Desenvolvido por **ZIJIU522**, sob a [MIT License](LICENSE).
