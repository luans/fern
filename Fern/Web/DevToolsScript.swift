import WebKit

/// Script do inspetor do Fern. O WebKit não tem API pública para abrir o inspetor dele
/// num app (só `isInspectable`, que liga o Web Inspector do Safari), então o Fern tem o
/// seu, mais simples.
///
/// Este script roda no mundo da página (o console que interessa é o dela), só no frame
/// principal. Ele guarda as mensagens do console e os erros desde o início do
/// carregamento, para o inspetor mostrar mesmo se for aberto depois. Não envia nada:
/// o painel busca as mensagens enquanto está aberto.
@MainActor
enum DevToolsScript {
    /// Nome do objeto na página. Não aparece em `Object.keys(window)`.
    static let bridge = "__fernDevtools"

    private static let installed = NSHashTable<WKUserContentController>.weakObjects()

    static func install(in controller: WKUserContentController) {
        guard !installed.contains(controller) else { return }
        installed.add(controller)
        controller.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
    }

    private static let source = """
        (() => {
          if (window.\(bridge)) return;
          const buffer = [];
          const limit = 500;

          const format = (value) => {
            if (typeof value === 'string') return value;
            if (value instanceof Error) return value.stack || String(value);
            if (value instanceof Element) return value.outerHTML.slice(0, 300);
            try {
              const json = JSON.stringify(value, null, 2);
              return json === undefined ? String(value) : json;
            } catch (error) {
              return String(value);
            }
          };

          const push = (level, args) => {
            buffer.push({ level, message: Array.from(args).map(format).join(' '), time: Date.now() });
            if (buffer.length > limit) buffer.splice(0, buffer.length - limit);
          };

          for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
            const original = console[level];
            console[level] = function (...args) {
              push(level, args);
              return original.apply(this, args);
            };
          }
          window.addEventListener('error', (event) => {
            const place = event.filename ? ` (${event.filename}:${event.lineno})` : '';
            push('error', [event.message + place]);
          });
          window.addEventListener('unhandledrejection', (event) => {
            push('error', ['Unhandled promise rejection: ' + format(event.reason)]);
          });

          const describe = (node, budget) => {
            if (budget.count-- <= 0) return null;
            if (node.nodeType === Node.TEXT_NODE) {
              const text = node.textContent.trim();
              return text ? { text: text.slice(0, 120) } : null;
            }
            if (node.nodeType !== Node.ELEMENT_NODE) return null;
            const element = { tag: node.tagName.toLowerCase() };
            if (node.id) element.id = node.id;
            if (node.classList.length) element.classes = Array.from(node.classList).slice(0, 4).join('.');
            const children = [];
            for (const child of node.childNodes) {
              const described = describe(child, budget);
              if (described) children.push(described);
            }
            if (children.length) element.children = children;
            return element;
          };

          Object.defineProperty(window, '\(bridge)', {
            enumerable: false,
            value: {
              drain: () => JSON.stringify(buffer.splice(0)),
              dom: () => JSON.stringify(describe(document.documentElement, { count: 4000 })),
              html: () => document.documentElement.outerHTML,
              network: () => JSON.stringify(performance.getEntriesByType('resource').map((entry) => ({
                url: entry.name,
                type: entry.initiatorType,
                size: entry.transferSize,
                duration: entry.duration,
                start: entry.startTime,
              }))),
            },
          });
        })();
        """
}
