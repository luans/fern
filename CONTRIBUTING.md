# Contribuindo com o Fern

Obrigado pelo interesse! O Fern quer continuar pequeno e legível, então prefira mudanças
focadas e bem explicadas.

## Rodando o projeto

1. Instale o Xcode 26 ou mais novo.
2. `make run` compila e abre o app. `make test` roda os testes unitários.
3. Antes de abrir um pull request, rode `make format` e `make lint`.

## Princípios

- **Sem dependências externas**, a não ser que a issue combine o contrário (a exceção
  prevista é o Sparkle, para atualizações).
- **Sem APIs privadas do WebKit.** Elas quebram a cada atualização do macOS.
- **Tudo que fala com o WebKit passa por `Web/`.** A interface conversa com `Tab` e
  `BrowserWindow`, não com `WKWebView` diretamente.
- **Textos de interface sempre localizados**, com tradução em português no
  `Resources/Localizable.xcstrings`.
- **Acessibilidade:** botões só com ícone precisam de rótulo (`Label` ou
  `accessibilityLabel`).

## Estilo de código

- Formatação com `swift-format` (configuração em `.swift-format`).
- Identificadores em inglês. Comentários podem ser em português.
- Swift 6 com concorrência estrita. Estado de interface é `@MainActor`.

## Propondo um experimento

Experimentos (Fase 5 do [spec](SPEC-browser.md)) moram em `Fern/Experiments/`, cada um no
seu arquivo ou pasta, e precisam poder ser ligados e desligados nas configurações. Abra uma
issue com o template "Experimento" antes de começar, descrevendo a ideia e o que ela
precisaria do núcleo.

## Pull requests

- Um assunto por pull request.
- Inclua testes para lógica nova (`FernTests/`).
- Descreva como testou manualmente, com capturas de tela quando a interface mudar.
