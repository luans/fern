# Spec — Navegador WebKit experimental para macOS

> Nome: **Fern** (antes "Simple")
> Status: rascunho v0.1 — outubro de 2026

## 1. Visão geral

Um navegador leve, simples e nativo para macOS, construído em Swift sobre o WebKit do próprio sistema (`WKWebView`). O objetivo não é competir com Safari ou Chrome em recursos, e sim ser uma base pequena, legível e fácil de modificar, que sirva de laboratório para ideias de interface e navegação. O projeto deve nascer pronto para ser open source.

### 1.1 Objetivos

- **Leve:** baixo uso de memória e CPU, inicialização rápida, app pequeno.
- **Simples:** poucos recursos, bem feitos. Interface mínima.
- **Nativo:** Swift + SwiftUI, seguindo as convenções do macOS (atalhos, menus, janelas).
- **Experimental:** arquitetura que facilite testar ideias novas sem mexer no núcleo.
- **Aberto:** código claro, documentado e com licença permissiva.

### 1.2 Fora de escopo (por enquanto)

- Windows, Linux, iOS ou iPadOS.
- Fork ou compilação do motor WebKit.
- Extensões do Chrome ou da Web Store.
- Sincronização entre dispositivos.
- Gerenciador de senhas próprio (usar o Preenchimento Automático e as Senhas do sistema quando possível).
- DRM avançado além do que o `WKWebView` já oferece no sistema.

## 2. Por que WebKit e não Chromium

| Critério | WebKit (`WKWebView`) | Fork do Chromium |
|---|---|---|
| Compilar o motor | Não precisa, já vem no macOS | Sim, ~100 GB de código e horas de build |
| Atualizações de segurança | Chegam com o macOS | Responsabilidade do projeto, a cada 4 semanas |
| Consumo de memória e bateria no Mac | Baixo | Mais alto |
| Tamanho do app | Poucos MB | Centenas de MB |
| Mexer no motor | Não é possível | Possível |
| Extensões do Chrome | Não | Sim |
| Multiplataforma | Só Apple (no escopo deste projeto) | Windows, macOS, Linux |

Conclusão: para um navegador leve, experimental e só para macOS, o `WKWebView` elimina o maior custo de um navegador (manter o motor) e deixa o projeto focado na interface.

## 3. Stack técnica

- **Linguagem:** Swift 6.
- **Interface:** SwiftUI, com AppKit quando necessário (menus, janelas, integração fina).
- **Motor:** WebKit via `WKWebView`, envolvido em `NSViewRepresentable`.
- **Persistência:** SwiftData (histórico e favoritos). Configurações em `UserDefaults`/`@AppStorage`.
- **IDE:** Xcode.
- **Atualizações automáticas (fase posterior):** Sparkle.
- **Dependências externas:** o mínimo possível. Idealmente apenas Sparkle.

### 3.1 Versão mínima do macOS

- **Decisão inicial:** macOS 14 (Sonoma) ou superior, usando `WKWebView` com `NSViewRepresentable`. Isso atinge mais usuários.
- **Alternativa:** exigir macOS 26 (Tahoe) e usar a nova `WebView`/`WebPage` nativa do SwiftUI, com código mais limpo.
- A camada de web fica isolada (ver seção 5) para que a troca futura seja simples.

## 4. Funcionalidades

As funcionalidades estão organizadas por fase. Cada fase deve terminar com o app utilizável.

### Fase 1 — Núcleo (MVP)

- Janela única com uma página web.
- Barra de endereço:
  - Aceita URL completa, domínio sem protocolo (adiciona `https://`) ou termo de busca.
  - Termos de busca vão para o buscador padrão (DuckDuckGo por padrão, configurável).
  - Mostra a URL atual e o ícone de cadeado quando a conexão é segura.
- Botões: voltar, avançar, recarregar/parar.
- Indicador de carregamento (barra de progresso fina).
- Título da janela igual ao título da página.
- Atalhos padrão:
  - `⌘L` focar barra de endereço
  - `⌘R` recarregar
  - `⌘[` / `⌘]` voltar e avançar
  - `⌘+` / `⌘-` / `⌘0` zoom
  - `⌘F` buscar na página
- Abertura de links externos (`mailto:`, `tel:` etc.) no app padrão do sistema.

### Fase 2 — Abas e janelas

- Múltiplas abas por janela.
  - `⌘T` nova aba, `⌘W` fechar aba, `⌘⇧T` reabrir última aba fechada.
  - `⌘1`…`⌘9` ir para a aba.
  - Links com `target="_blank"` e `⌘+clique` abrem em nova aba.
- Múltiplas janelas (`⌘N`).
- Layout de abas: começar com abas horizontais, com estrutura que permita abas verticais (ver Fase 5).
- Restaurar a sessão anterior ao abrir o app (opcional, configurável).

### Fase 3 — Histórico, favoritos e downloads

- **Histórico:** registro de URL, título e data. Busca simples. Opção de limpar tudo ou por período.
- **Favoritos:** lista simples, sem pastas no início. Adicionar com `⌘D`.
- **Sugestões na barra de endereço:** a partir do histórico e dos favoritos.
- **Downloads:** usando `WKDownload`. Salvar na pasta Downloads, com uma lista simples de downloads em andamento e concluídos.

### Fase 4 — Privacidade e bloqueio

- **Bloqueador de conteúdo** com `WKContentRuleList`:
  - Usa o formato JSON dos bloqueadores de conteúdo do Safari.
  - Lista inicial embutida no app (anúncios e rastreadores comuns).
  - Possibilidade de ativar/desativar por site.
  - Listas compiladas uma vez e guardadas em cache pelo `WKContentRuleListStore`.
- **Janela privada** (`⌘⇧N`) com `WKWebsiteDataStore.nonPersistent()`: nada de cookies, histórico ou cache persistidos.
- **Perfis isolados** (opcional): cada perfil com seu próprio `WKWebsiteDataStore` (`WKWebsiteDataStore(forIdentifier:)`, macOS 14+).
- Limpar dados de sites (cookies, cache, armazenamento local).
- HTTPS por padrão quando o usuário digitar só o domínio.

### Fase 5 — Experimental

Área livre para testar ideias. Cada experimento deve poder ser ligado ou desligado nas configurações (feature flags). Ideias iniciais:

- **Abas verticais** na lateral.
- **Barra de comandos** estilo Spotlight (`⌘K`): abrir URL, buscar abas abertas, histórico e ações.
- **Modo foco:** esconde toda a interface, deixando só a página.
- **Modo leitura** via `WKUserScript` (extração do conteúdo principal).
- **Tema escuro forçado** via CSS injetado.
- **Espaços de trabalho:** grupos de abas por contexto (trabalho, estudo, pessoal).
- **Abas que expiram:** abas não usadas há X horas são arquivadas automaticamente.
- **Scripts e estilos do usuário:** pasta onde o usuário coloca `.js`/`.css` aplicados por domínio.

## 5. Arquitetura

### 5.1 Princípios

- O núcleo (abas, navegação, persistência) fica separado da interface.
- Tudo que fala com o WebKit passa por uma camada própria (`WebEngine`), facilitando a troca para a nova API SwiftUI no futuro.
- Experimentos são módulos isolados que se registram no app, sem alterar o núcleo.

### 5.2 Componentes principais

| Componente | Responsabilidade |
|---|---|
| `BrowserApp` | Ponto de entrada, cenas, menus e comandos globais. |
| `BrowserWindow` | Estado de uma janela: lista de abas e aba ativa. |
| `Tab` | Estado de uma aba: URL, título, progresso, `canGoBack`/`canGoForward`, favicon. Dono de um `WKWebView`. |
| `WebEngine` | Cria e configura `WKWebView`/`WKWebViewConfiguration`, aplica regras de bloqueio e scripts. |
| `WebView` | `NSViewRepresentable` que exibe o `WKWebView` da aba. |
| `NavigationDelegate` | Implementa `WKNavigationDelegate` e `WKUIDelegate`: novas janelas, downloads, links externos, erros. |
| `AddressBarParser` | Decide se o texto digitado é URL, domínio ou busca. |
| `HistoryStore` / `BookmarkStore` | Persistência com SwiftData. |
| `ContentBlocker` | Carrega, compila e aplica as listas de bloqueio. |
| `Settings` | Preferências do usuário e feature flags. |
| `Experiments/` | Um módulo por experimento. |

### 5.3 Estrutura de pastas sugerida

```
NomeDoApp/
├── App/
│   ├── BrowserApp.swift
│   └── Commands.swift
├── Core/
│   ├── BrowserWindow.swift
│   ├── Tab.swift
│   └── AddressBarParser.swift
├── Web/
│   ├── WebEngine.swift
│   ├── WebView.swift
│   └── NavigationDelegate.swift
├── Storage/
│   ├── HistoryStore.swift
│   └── BookmarkStore.swift
├── Privacy/
│   ├── ContentBlocker.swift
│   └── Resources/blocklist.json
├── UI/
│   ├── ContentView.swift
│   ├── AddressBar.swift
│   ├── TabBar.swift
│   └── SettingsView.swift
├── Experiments/
│   └── (um arquivo ou pasta por experimento)
└── Resources/
    └── Assets.xcassets
```

### 5.4 Fluxo da barra de endereço

1. Usuário digita e pressiona Enter.
2. `AddressBarParser` classifica o texto:
   - Tem esquema (`https://`, `http://`, `file://`)? Usa como está.
   - Parece domínio (contém ponto, sem espaços, ou é `localhost`)? Adiciona `https://`.
   - Caso contrário, monta a URL de busca do buscador padrão.
3. A aba ativa chama `webView.load(URLRequest(url:))`.
4. O `NavigationDelegate` atualiza URL, título e progresso da aba.

## 6. Requisitos não funcionais

- **Desempenho:** abrir o app em menos de 1 segundo em um Mac Apple Silicon. Nova aba vazia sem custo perceptível.
- **Memória:** abas em segundo plano por muito tempo podem ser descarregadas e recarregadas ao voltar (avaliar na Fase 5).
- **Tamanho:** app final com poucos MB, sem frameworks pesados.
- **Acessibilidade:** VoiceOver funcionando na interface própria (barra de endereço, abas, botões).
- **Idioma:** interface em português e inglês desde o início (String Catalogs do Xcode).
- **Segurança:**
  - Sandbox do macOS habilitado (App Sandbox) com as permissões mínimas: rede de saída e acesso à pasta Downloads.
  - Nunca executar scripts de origem não confiável fora do contexto da página.
  - Mostrar claramente quando a conexão não é segura.

## 7. Open source

- **Licença:** MIT (simples e permissiva). Alternativa: GPLv3, se a intenção for obrigar forks a continuarem abertos.
- **Repositório:** GitHub, público desde o início, com:
  - `README.md` (o que é, capturas de tela, como compilar)
  - `LICENSE`
  - `CONTRIBUTING.md` (como rodar, estilo de código, como propor experimentos)
  - `CODE_OF_CONDUCT.md`
  - Templates de issue e pull request
- **CI:** GitHub Actions compilando e rodando testes em cada pull request (runner macOS).
- **Estilo de código:** SwiftFormat ou swift-format com configuração no repositório.

## 8. Distribuição

- **Fase inicial:** releases no GitHub com o `.app` compactado. Sem assinatura, o Gatekeeper exibe aviso e o usuário precisa liberar o app manualmente; documentar isso no README.
- **Fase madura:**
  - Conta Apple Developer (US$ 99/ano) para assinar com Developer ID e notarizar.
  - Atualizações automáticas com Sparkle (feed `appcast.xml` hospedado no GitHub Pages ou nas releases).
  - Cask no Homebrew (`brew install --cask nome-do-app`).
- Mac App Store: fora do escopo inicial (regras de sandbox e revisão mais restritivas).

## 9. Testes

- **Unitários:** `AddressBarParser`, stores de histórico e favoritos, lógica de abas.
- **Interface:** testes básicos com XCUITest (abrir app, digitar URL, abrir e fechar aba).
- **Manual:** lista de verificação por release (sites populares, vídeos, login, downloads, janela privada, bloqueador).

## 10. Roadmap resumido

| Fase | Entrega | Resultado |
|---|---|---|
| 1 | Núcleo | Navega em uma aba com barra de endereço e atalhos |
| 2 | Abas e janelas | Uso diário básico possível |
| 3 | Histórico, favoritos, downloads | Navegador completo para uso simples |
| 4 | Privacidade e bloqueio | Diferencial de leveza e privacidade |
| 5 | Experimental | Identidade própria do projeto |
| — | Open source e distribuição | Repositório público, releases e, depois, assinatura e Homebrew |

## 11. Riscos e limitações conhecidas

- **Sem acesso ao motor:** só é possível usar o que o `WKWebView` expõe. Recursos que exigem mexer no WebKit ficam fora.
- **Compatibilidade de sites:** alguns sites são testados só no Chrome e podem ter problemas no WebKit.
- **Extensões:** não há suporte nativo a extensões do Chrome nem do Safari no `WKWebView`. Personalizações ficam via scripts do usuário e bloqueador.
- **APIs privadas:** algumas funções do Safari usam APIs internas. O projeto não deve usar APIs privadas, para não quebrar a cada atualização do macOS.
- **Gatekeeper:** sem assinatura, a experiência de instalação é ruim para usuários comuns.

## 12. Decisões em aberto

- [x] Nome do projeto: Fern.
- [ ] macOS 14+ com `WKWebView` ou macOS 26+ com a `WebView` nativa do SwiftUI.
- [ ] Licença: MIT ou GPLv3.
- [ ] Buscador padrão e opções oferecidas.
- [ ] Origem da lista de bloqueio inicial (lista própria ou conversão de listas públicas, verificando a licença de cada uma).
- [ ] Quais experimentos da Fase 5 entram primeiro.
- [ ] Restaurar sessão por padrão ou não.
