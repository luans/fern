import WebKit

/// Descobre se uma aba está fazendo som e permite silenciá-la.
///
/// O WebKit não diz se uma página está tocando som (`requestMediaPlaybackState` conta
/// até vídeos mudos de fundo) nem deixa silenciar uma página. Por isso o Fern injeta um
/// script pequeno em cada frame, no mundo isolado do app (`.defaultClient`), que a página
/// não vê nem altera. Ele observa os `<video>` e `<audio>` e avisa quando passa a sair ou
/// deixa de sair som; para silenciar, deixa os elementos mudos e continua tocando.
///
/// Limitação: sons do Web Audio (jogos, alguns players) e `new Audio()` fora da página
/// não passam por esses elementos e não são detectados nem silenciados.
@MainActor
final class MediaObserver: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = MediaObserver()

    static let handlerName = "fernMedia"

    /// Controladores que já têm o script e o receptor. Abas abertas por `target="_blank"`
    /// podem compartilhar o controlador da aba de origem, e registrar duas vezes o mesmo
    /// nome de receptor encerra o app.
    private let installed = NSHashTable<WKUserContentController>.weakObjects()

    func install(in controller: WKUserContentController) {
        guard !installed.contains(controller) else { return }
        installed.add(controller)
        controller.addUserScript(
            WKUserScript(
                source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
        controller.addScriptMessageHandler(self, contentWorld: .defaultClient, name: Self.handlerName)
    }

    /// Cada aviso de um frame: `{ frame: id, audible: Bool }`. A resposta diz ao frame se a
    /// aba está silenciada, para ele já começar mudo.
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any], let frameID = body["frame"] as? String,
            let tab = (message.webView?.navigationDelegate as? NavigationDelegate)?.tab
        else {
            replyHandler(["muted": false], nil)
            return
        }
        let audible = body["audible"] as? Bool ?? false
        let muted = tab.mediaFrame(frameID, didReportAudible: audible, frame: message.frameInfo)
        replyHandler(["muted": muted], nil)
    }

    /// Roda em cada frame. `window.__fernMedia` só existe no mundo isolado do Fern.
    private static let script = """
        (() => {
          if (window.__fernMedia) return;
          const handler = window.webkit?.messageHandlers?.\(handlerName);
          if (!handler) return;

          const frame = Math.random().toString(36).slice(2);
          const mutedByFern = new WeakSet();
          let muted = false;
          let lastAudible = null;

          const elements = () => Array.from(document.querySelectorAll('video, audio'));

          // Sai som (ou sairia, se o Fern não tivesse silenciado o elemento).
          const isAudible = (el) =>
            !el.paused && !el.ended && el.volume > 0 && (!el.muted || mutedByFern.has(el));

          const apply = (el) => {
            if (muted && !el.muted) { el.muted = true; mutedByFern.add(el); }
            if (!muted && mutedByFern.has(el)) { el.muted = false; mutedByFern.delete(el); }
          };

          const report = (force) => {
            const audible = elements().some(isAudible);
            if (!force && audible === lastAudible) return;
            lastAudible = audible;
            handler.postMessage({ frame, audible }).then((reply) => {
              if (reply && reply.muted !== muted) setMuted(reply.muted);
            }).catch(() => {});
          };

          const setMuted = (value) => {
            muted = value;
            elements().forEach(apply);
            report(true);
          };

          for (const type of ['play', 'playing', 'pause', 'ended', 'volumechange', 'emptied']) {
            document.addEventListener(type, (event) => {
              if (event.target instanceof HTMLMediaElement) apply(event.target);
              report(false);
            }, true);
          }
          window.addEventListener('pagehide', () => {
            handler.postMessage({ frame, audible: false }).catch(() => {});
          });

          window.__fernMedia = { setMuted };
          report(true);
        })();
        """
}
