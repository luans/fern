<p align="center">
  <img src="Fern/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="Ícone do Fern: um broto de samambaia se desenrolando">
</p>

# Fern

Um navegador leve, simples e nativo para macOS, feito em Swift e SwiftUI sobre o WebKit do
próprio sistema (`WKWebView`). Não quer competir com Safari ou Chrome: é uma base pequena e
legível para testar ideias de interface e navegação, com a cara de um app de Mac.

> **Status:** v0.6. Fases 1 a 4 do [spec](SPEC-browser.md) prontas (núcleo, abas, histórico,
> favoritos, downloads e privacidade), mais perfis, câmera e microfone, inspetor e os primeiros
> experimentos da Fase 5.

## Sumário

- [Funcionalidades](#funcionalidades)
- [Atalhos de teclado](#atalhos-de-teclado)
- [Ajustes](#ajustes)
- [Como compilar e rodar](#como-compilar-e-rodar)
- [Testes](#testes)
- [Distribuição](#distribuição)
- [Arquitetura](#arquitetura)
- [Dados salvos](#dados-salvos)
- [Sandbox e permissões](#sandbox-e-permissões)
- [Limitações conhecidas](#limitações-conhecidas)
- [Roadmap](#roadmap)
- [Contribuindo](#contribuindo)

## Funcionalidades

### Visual

- Moldura própria, sem barra de título: fundo cinza e fosco, a página flutuando num cartão com
  cantos arredondados, e os botões fechar, minimizar e tela cheia desenhados pelo Fern,
  alinhados à primeira linha da interface.
- Faixa superior com voltar, avançar, recarregar, a barra de endereço e, à direita, perfil,
  ajustes e downloads.
- Segue o modo claro ou escuro do sistema. A cor de destaque é o verde da samambaia.
- As áreas vazias da moldura arrastam a janela; clique duplo amplia (ou minimiza, conforme o
  ajuste do macOS).
- Interface em inglês e português.

### Navegação e barra de endereço

- Entende URL completa, domínio sem protocolo (completa com `https://`) e termos de busca.
  `localhost`, `*.localhost` e IPs abrem com `http://`, porque servidores locais quase nunca
  têm certificado.
- Buscador padrão DuckDuckGo; Google, Bing, Brave Search e Ecosia nos ajustes.
- Cadeado para conexões seguras e aviso "Não seguro" para HTTP.
- **Sugestões enquanto você digita:** abas abertas (com "Ir para a Aba"), favoritos (★) e
  histórico, cada endereço uma vez só. Setas para escolher, Enter para abrir, Esc para fechar.
- Barra de progresso fina, título da janela igual ao da página, busca na página e zoom.
- Links `mailto:`, `tel:` e de outros apps abrem no app padrão, só a partir de um clique seu.
- Páginas de erro com "Tentar novamente"; arquivos que a página pede para baixar viram
  downloads.

### Abas e barra lateral

- Abas num cartão na barra lateral, com ícone do site, indicador de carregamento e menu de
  contexto. Arraste uma aba sobre outra para reordenar.
- Links com `target="_blank"` abrem em nova aba; `⌘`+clique ou clique do meio abrem em
  segundo plano (com `⇧`, em primeiro plano). Pop-ups de login continuam ligados à página que
  os abriu.
- A barra lateral muda de largura arrastando a borda dela (180 a 420 pontos). Clique duplo na
  borda volta ao padrão; arrastar bem para a esquerda esconde a barra (`⌃⌘S` traz de volta).
- **Grade:** abas como ícones no topo da barra lateral, para os sites que você usa sempre.
- **Fixadas:** abas como cards no topo do cartão de abas, separadas das demais por uma linha.
- A grade e as fixadas voltam quando o app abre e só carregam quando você clica nelas.
  Para colocar ou tirar uma aba: menu de contexto, menu Arquivo ou arrastar a aba sobre um
  ícone da grade ou sobre uma fixada.
- `⌘⇧T` reabre a última aba fechada (inclusive da grade ou fixada, no lugar dela).

### Favoritos

- Lista de páginas salvas, independente das abas: fechar a aba não apaga o favorito.
- `⌘D` ou a ★ na barra de endereço salva a página; a estrela fica amarela quando a página já é
  favorita, e clicar nela permite renomear ou remover.
- `⌥⌘B` (ou "Favoritos" na barra lateral) abre a lista: busca, ícone de cada site, clique para
  abrir (com `⌘` numa aba nova), reordenar arrastando, renomear, copiar link e apagar.
- Menu **Favoritos** na barra de menus com os 20 primeiros.

### Histórico

- Cada página visitada entra no histórico do perfil (só páginas da web, não as privadas).
- `⌘Y` abre a lista: busca por título ou endereço, entradas agrupadas por dia, clique para
  abrir numa aba nova e limpeza por período (última hora, hoje, hoje e ontem, tudo).

### Perfis

- Cada perfil tem suas próprias **abas, grade, fixadas, favoritos, histórico, permissões e
  dados de sites** (cookies, logins, cache). Ex.: "Pessoal" e "Trabalho" logados em contas
  diferentes do mesmo site ao mesmo tempo.
- Seletor no rodapé da barra lateral: o perfil ativo aparece com o nome; os outros, como
  pontos coloridos. `+` cria um perfil com nome e cor.
- Deslize dois dedos na horizontal sobre a barra lateral para ir ao próximo perfil ou ao
  anterior. Depois do último, o gesto cria um **perfil rascunho**, que só é salvo quando você
  abre uma página nele (ou o renomeia); se você sair dele sem usar, ele some.
- O avatar no topo também troca de perfil. Novas janelas abrem no último perfil usado.
- O perfil "Pessoal" é o padrão e não pode ser apagado. Apagar um perfil fecha as abas dele e
  remove os dados dele deste Mac.

### Continuar de onde parou

- Ao abrir, o Fern reabre as abas da última sessão de cada perfil, na mesma ordem e com a
  mesma aba ativa. Só a aba ativa carrega na hora; as outras, quando você clicar.
- Ligado por padrão; dá para desligar em Ajustes › Geral.

### Downloads

- Links de download, arquivos que o WebKit não exibe e respostas marcadas para baixar vão
  para a pasta Downloads (nomes repetidos viram "arquivo 2.pdf").
- O botão de downloads mostra um anel de progresso; a lista abre sozinha quando um download
  começa (ou com `⌥⌘L`), com cancelar, mostrar no Finder e abrir com clique duplo.
- Os concluídos ficam na lista entre execuções (exceto os de janelas privadas).

### Privacidade

- **Bloqueio de anúncios e rastreadores** com `WKContentRuleList`, a partir de uma lista
  própria de domínios conhecidos, bloqueados só quando vêm de outro site (para não quebrar o
  site do próprio serviço). Dá para desligar por site, no botão de ajustes do site, ou de vez,
  em Ajustes › Privacidade.
- **Janela privada** (`⌘⇧N`): sempre escura, com o selo "Navegação Privada". Não grava
  histórico, sessão, grade nem fixadas, e os cookies e dados de sites ficam só na memória e
  somem ao fechar a janela.
- **Limpar dados de navegação** por perfil e período: histórico, cookies e dados de sites, e
  cache.
- HTTPS por padrão ao digitar só o domínio.

### Câmera, microfone e som

- Sites podem usar a câmera e o microfone (chamadas de vídeo, mensagens de voz). Na primeira
  vez, o macOS pergunta se o Fern pode usar o dispositivo; depois, o Fern pergunta na própria
  página, com a opção de lembrar a escolha para o site (por perfil). Se o macOS estiver
  bloqueando o Fern, o pedido avisa e leva aos Ajustes do Sistema.
- Abas usando a câmera ou o microfone mostram ícones vermelhos na lista (clique para pausar
  ou religar) e um ponto vermelho na grade.
- O **botão de ajustes do site**, na barra de endereço, fica vermelho durante o uso e permite
  pausar, parar e mudar as permissões de câmera, microfone e bloqueio do site.
- Compartilhamento de tela funciona pelo seletor do próprio macOS (ver
  [limitações](#limitações-conhecidas)).
- **Ícone de som** nas abas que estão fazendo som de verdade (vídeos mudos de fundo não
  contam) e **silenciar aba**: clique no ícone, menu de contexto da aba ou menu Janela. Os
  vídeos continuam tocando, sem som, inclusive os que começarem depois.
- Reprodução automática configurável: permitir tudo, parar mídia com som (padrão) ou nunca.

### Inspetor (ferramentas de desenvolvedor)

- `F12` ou `⌥⌘I` (menu Desenvolvedor) abre o inspetor do Fern embaixo da página, com altura
  ajustável arrastando a borda de cima.
- **Elementos:** árvore do HTML (tag, id e classes) e o código-fonte da página.
- **Console:** `console.log`, avisos, erros e promises rejeitadas da página desde o
  carregamento, e um campo para rodar JavaScript nela (funciona mesmo em sites que bloqueiam
  `eval`).
- **Rede:** recursos carregados, com tipo, tamanho e tempo.
- Para o Web Inspector completo do WebKit (estilos, depurador, armazenamento): no Safari,
  ative o menu Desenvolvedor em Ajustes › Avançado e escolha Desenvolvedor › este Mac › Fern.

### Experimentos

Ideias em teste, cada uma com uma chave em Ajustes › Experimentos:

- **Monitor do sistema** (ligado por padrão): CPU, memória e estado térmico do Mac no rodapé
  da barra lateral, com gráfico do último minuto e detalhes ao clicar, incluindo a CPU e a
  memória do processo principal do Fern.

## Atalhos de teclado

| Atalho | Ação |
|---|---|
| `⌘N` / `⌘⇧N` | Nova janela / nova janela privada |
| `⌘T` / `⌘W` | Nova aba / fechar aba (a última fecha a janela) |
| `⌘⇧T` | Reabrir a última aba fechada |
| `⌘1`…`⌘8` / `⌘9` | Ir para a aba / ir para a última aba |
| `⌘⇧]` / `⌘⇧[` | Próxima aba / aba anterior |
| `⌃⌘S` | Mostrar ou esconder a barra lateral |
| `⌘L` | Focar a barra de endereço |
| `⌘R` / `⌘.` | Recarregar / parar |
| `⌘[` / `⌘]` | Voltar / avançar |
| `⌘+` (ou `⌘=`) / `⌘-` / `⌘0` | Aumentar zoom / reduzir / tamanho real |
| `⌘F` / `⌘G` / `⌘⇧G` | Buscar na página / próxima / anterior |
| `⌘D` / `⌥⌘B` | Salvar a página nos Favoritos / mostrar os Favoritos |
| `⌘Y` | Histórico |
| `⌥⌘L` | Downloads |
| `F12` ou `⌥⌘I` | Inspetor (no MacBook, `fn`+`F12`) |
| `⌘,` | Ajustes |
| `Esc` | Cancelar a edição do endereço, fechar as sugestões ou fechar a busca |

Sem atalho, nos menus: Arquivo › Fixar Aba e Adicionar à Grade; Janela › Silenciar Aba.

## Ajustes

| Aba | O que tem |
|---|---|
| **Geral** | Continuar de onde parou e buscador padrão |
| **Privacidade** | Bloqueio de anúncios e rastreadores, sites com o bloqueio desligado e limpar dados de navegação |
| **Sites** | Reprodução automática e permissões de câmera e microfone de cada site, por perfil |
| **Perfis** | Criar, renomear, mudar a cor e apagar perfis |
| **Experimentos** | Ligar ou desligar cada experimento |

## Como compilar e rodar

**Requisitos:** macOS 14 ou superior para rodar; Xcode 26 para compilar. Não há dependências
externas.

```bash
make run
```

| Comando | O que faz |
|---|---|
| `make build` | Compila em Debug |
| `make run` | Compila em Debug e abre o app |
| `make test` | Testes unitários |
| `make ui-test` | Testes de interface (XCUITest) |
| `make format` | Formata o código com `swift-format` |
| `make lint` | Verifica o estilo com `swift-format` |
| `make release` | Gera o zip de distribuição (ver [Distribuição](#distribuição)) |
| `make clean` | Apaga a pasta `build/` |

Também dá para abrir `Fern.xcodeproj` no Xcode e usar `⌘R`.

**Scripts:**

- `swift scripts/make-icon.swift`: gera o ícone em todos os tamanhos. Com um caminho no fim,
  gera só uma prévia em 1024 px.
- `python3 scripts/make-blocklist.py`: gera a lista de bloqueio a partir de
  `scripts/blocklist-domains.txt`. Depois de mudar a lista, aumente a versão em
  `ruleListIdentifier` (`Fern/Privacy/ContentBlocker.swift`), senão o WebKit continua usando a
  versão em cache.

## Testes

- **Unitários** (`FernTests/`, Swift Testing): barra de endereço, janela e abas (grade,
  fixadas, reordenar, sessão, perfis, rascunho, janela privada, sugestões), histórico,
  favoritos, permissões de sites, áudio da aba, bloqueador, downloads, inspetor e as leituras
  do monitor do sistema. Cada teste usa armazenamento próprio (`UserDefaults` e SwiftData em
  memória), sem tocar nos dados do app.
- **Interface** (`FernUITests/`, XCUITest): abrir o app, digitar um endereço, abrir e fechar
  abas. Rodam na tela de verdade: não mexa no teclado nem no mouse enquanto rodam.
- **Manual:** sites populares, vídeos e chamadas, login, downloads, janela privada,
  bloqueador e perfis.

## Distribuição

```bash
make release
```

Gera `build/Fern-<versão>.zip` com o app em Release, universal (Apple Silicon e Intel), e o
`Fern-<versão>.zip.sha256` ao lado. A versão vem de `MARKETING_VERSION` no projeto; para
outra, sem editar o projeto: `make release VERSION=0.7.0 BUILD_NUMBER=42`.

### Publicar uma versão

O workflow [Release](.github/workflows/release.yml) roda o lint, gera o zip e cria a
GitHub Release com o zip e o SHA-256 anexados e as notas geradas a partir dos PRs e commits.
Dois jeitos de disparar:

- **Tag:** `git tag v0.7.0 && git push origin v0.7.0`.
- **Pela aba Actions:** Release › Run workflow, com a versão (ex.: `0.7.0`). O workflow cria a
  tag no commit escolhido.

Versões com sufixo (`0.7.0-beta.1`) saem como pré-lançamento. O número de build do app é o
número da execução do workflow.

Cada push na `main` também gera um zip de teste (`<versão>-dev.<execução>`), guardado por 14
dias em Actions › execução › Artifacts.

## Arquitetura

### Princípios

- **Tudo que fala com o WebKit passa por `Web/`.** A interface conversa com `Tab` e
  `BrowserWindow`, não com `WKWebView` diretamente. Isso facilita trocar para a
  `WebView`/`WebPage` nativa do SwiftUI no futuro.
- **Só APIs públicas.** Quando o WebKit não oferece algo (abrir o inspetor dele, silenciar
  uma página, saber se ela faz som), o Fern implementa o mínimo por conta própria ou documenta
  a limitação.
- **Experimentos isolados**, cada um em `Experiments/` com uma chave nos ajustes, sem mexer
  no núcleo.
- Swift 6 com concorrência estrita; o estado de interface é `@MainActor` e `@Observable`.

### Pastas

```
Fern/
├── App/          ponto de entrada (FernApp), menus e atalhos (Commands)
├── Core/         estado das janelas e abas, perfis, histórico, favoritos, permissões,
│                 barra de endereço e ajustes
├── Web/          WebKit: WebEngine, WebView, NavigationDelegate, downloads, ícones de
│                 sites e os scripts injetados (som e inspetor)
├── Privacy/      bloqueador de conteúdo e a lista de bloqueio
├── UI/           views SwiftUI: moldura, barra lateral, faixa superior, ajustes, painéis
├── Experiments/  experimentos da Fase 5 (hoje, o monitor do sistema)
└── Resources/    ícone, cor de destaque e traduções (String Catalogs)
FernTests/        testes unitários
FernUITests/      testes de interface
scripts/          ícone e lista de bloqueio
```

### Componentes principais

| Componente | Papel |
|---|---|
| `FernApp`, `Commands` | Cenas (janela comum, janela privada, ajustes), menus e atalhos |
| `BrowserWindow` | Estado de uma janela: perfil em uso, abas de cada perfil, aba ativa, sessão, grade e fixadas |
| `Tab` | Estado de uma aba e dona do seu `WKWebView` (URL, título, progresso, segurança, zoom, câmera, microfone, som) |
| `WebEngine` | Cria e configura os `WKWebView`, com o armazenamento de dados de cada perfil |
| `NavigationDelegate` | Navegação, novas abas, links externos, downloads, diálogos de JavaScript e pedidos de câmera e microfone |
| `AddressBarParser` | Decide se o texto digitado é URL, domínio ou busca |
| `ProfileStore` | Lista de perfis (e o rascunho) |
| `HistoryStore`, `BookmarkStore` | Histórico e favoritos, com SwiftData |
| `SitePermissionStore` | Decisões de câmera e microfone por site e perfil |
| `ContentBlocker` | Compila e aplica a lista de bloqueio, com exceções por site |
| `DownloadManager` | Downloads com `WKDownload` |
| `MediaObserver` | Script que detecta som e silencia a aba |
| `DevToolsScript`, `DevToolsSession` | O inspetor: script na página e o estado do painel |
| `FaviconLoader` | Ícones dos sites, com cache por domínio |
| `Theme`, `WindowConfigurator` | Cores, medidas e a moldura própria da janela |

### Scripts injetados nas páginas

| Script | Mundo | Para quê |
|---|---|---|
| `MediaObserver` | Isolado do app (`.defaultClient`), todos os frames | Saber se sai som e silenciar a aba. A página não vê nem altera o script. |
| `DevToolsScript` | Da página (`.page`), frame principal | Guardar as mensagens do console desde o carregamento e montar a árvore do HTML. |
| Busca do ícone do site | Isolado do app | Achar o `<link rel="icon">` da página. |

## Dados salvos

Tudo fica neste Mac, dentro da pasta do sandbox do app.

| O quê | Onde |
|---|---|
| Histórico | SwiftData (`History.store`) |
| Favoritos | SwiftData (`Bookmarks.store`) |
| Perfis e último perfil usado | `UserDefaults` (`profiles`, `lastUsedProfileID`) |
| Grade, fixadas e sessão de cada perfil | `UserDefaults` (`pinnedTabs`, `pinnedTabRows`, `session.<perfil>`) |
| Permissões de sites | `UserDefaults` (`sitePermissions`) |
| Exceções do bloqueador | `UserDefaults` (`contentBlocker.allowedHosts`) |
| Lista de downloads | `UserDefaults` (`downloads`) |
| Ajustes e preferências de interface | `UserDefaults` (buscador, sessão, bloqueio, reprodução automática, experimentos, larguras e alturas) |
| Cookies, logins, cache e armazenamento dos sites | WebKit: o perfil padrão usa o armazenamento padrão; cada outro perfil tem o seu (`WKWebsiteDataStore(forIdentifier:)`); janelas privadas, só na memória |

## Sandbox e permissões

O app roda no App Sandbox com o hardened runtime ligado e só estas permissões:

| Permissão | Para quê |
|---|---|
| Rede (saída) | Carregar páginas |
| Pasta Downloads | Salvar downloads |
| Arquivos escolhidos por você (leitura) | `<input type="file">` |
| Câmera e microfone | Sites que você permitir; o macOS pede autorização na primeira vez |

## Limitações conhecidas

O Fern usa o WebKit do sistema e só APIs públicas, então algumas coisas ficam de fora:

- **Extensões** do Chrome e do Safari não são suportadas.
- **Compartilhamento de tela** funciona pelo seletor do macOS, mas fica fora dos controles do
  Fern: não há permissão por site nem ícone na aba. Para parar, use o botão do site ou o
  indicador do macOS na barra de menus.
- **Som:** sons de Web Audio (jogos, alguns players) e `new Audio()` fora da página não
  acendem o ícone de som nem são silenciados.
- **Inspetor:** sem edição de estilos, depurador, armazenamento ou cabeçalhos HTTP; o console
  só captura o frame principal. O script do console fica na página, que poderia detectar que
  o `console.log` foi modificado.
- **Monitor do sistema:** a temperatura em graus não aparece (o macOS não tem API pública), e
  o consumo do Fern mostra só o processo principal (o sandbox não deixa medir os processos do
  WebKit, onde as páginas rodam).
- **Sessão:** com várias janelas, vale a que salvou por último, e as abas restauradas voltam
  sem o histórico de voltar e avançar.
- **Bloqueador:** a primeira página depois de abrir o app pode carregar antes de as regras
  estarem prontas.

## Roadmap

| Fase | Entrega | Situação |
|---|---|---|
| 1 | Núcleo: uma aba, barra de endereço e atalhos | Pronta |
| 2 | Abas e janelas | Pronta |
| 3 | Histórico, favoritos e downloads | Pronta |
| 4 | Privacidade e bloqueio | Pronta |
| 5 | Experimental | Em andamento |

Feito na Fase 5: abas verticais, perfis com espaços, monitor do sistema e o registro de
experimentos. Ideias ainda abertas: barra de comandos (`⌘K`), modo foco, modo leitura, tema
escuro forçado, abas que expiram, scripts e estilos do usuário por domínio. Na distribuição:
assinatura com Developer ID, notarização, atualizações automáticas (Sparkle) e Homebrew.

## Contribuindo

Veja [CONTRIBUTING.md](CONTRIBUTING.md) e o [código de conduta](CODE_OF_CONDUCT.md).

## Licença

[MIT](LICENSE).
