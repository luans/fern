import AppKit
import WebKit

/// Recebe os eventos do `WKWebView` de uma aba: navegação, novas janelas, links
/// externos, erros e os diálogos de JavaScript (`alert`, `confirm`, `prompt`).
@MainActor
final class NavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var tab: Tab?

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        // Links com o atributo `download` viram download direto.
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if WebEngine.canLoadInWebView(url) {
            // ⌘+clique ou clique do meio num link: abre em nova aba, em segundo plano
            // (com Shift, em primeiro plano), como no Safari.
            if navigationAction.navigationType == .linkActivated, Self.wantsNewTab(navigationAction),
                let window = tab?.browserWindow
            {
                decisionHandler(.cancel)
                window.newTab(url: url, activate: navigationAction.modifierFlags.contains(.shift))
                return
            }
            // As regras de bloqueio dependem do site da página principal.
            if navigationAction.targetFrame?.isMainFrame ?? true {
                ContentBlocker.shared.apply(to: webView, loading: url)
            }
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        // Links externos (mailto:, tel:, apps) só abrem a partir de um clique do usuário,
        // nunca por redirecionamento automático da página.
        if navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
        }
    }

    /// Arquivos que o WebKit não sabe exibir, ou que o servidor manda baixar
    /// (`Content-Disposition: attachment`), viram download.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let disposition =
            (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if navigationResponse.isForMainFrame, disposition.hasPrefix("attachment") || !navigationResponse.canShowMIMEType
        {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        DownloadManager.shared.track(download, from: tab?.browserWindow)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        DownloadManager.shared.track(download, from: tab?.browserWindow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab?.navigationDidStart()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        tab?.navigationDidFail(with: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        tab?.navigationDidFail(with: error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab?.navigationDidFinish()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private static func wantsNewTab(_ action: WKNavigationAction) -> Bool {
        // buttonNumber 2 é o botão do meio do mouse.
        action.modifierFlags.contains(.command) || action.buttonNumber == 2
    }

    // MARK: - WKUIDelegate

    /// Links com `target="_blank"` e `window.open` viram uma nova aba. O web view
    /// devolvido precisa usar a `configuration` recebida, e o WebKit carrega a página
    /// nele sozinho. Pop-ups sem gesto do usuário já são bloqueados pelo WebKit.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let window = tab?.browserWindow else {
            webView.load(navigationAction.request)
            return nil
        }
        let inBackground = Self.wantsNewTab(navigationAction) && !navigationAction.modifierFlags.contains(.shift)
        return window.newTab(configuration: configuration, activate: !inBackground).webView
    }

    /// A página chamou `window.close()` (comum em pop-ups de login).
    func webViewDidClose(_ webView: WKWebView) {
        guard let tab, let window = tab.browserWindow else { return }
        window.closeTab(tab.id)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = Self.makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: String(localized: "OK"))
        present(alert, over: webView) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = Self.makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        present(alert, over: webView) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = Self.makeAlert(message: prompt, frame: frame)
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        present(alert, over: webView) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    /// `getUserMedia`: a página quer a câmera e/ou o microfone. Usa a decisão salva para
    /// o site ou pergunta na própria aba. O macOS ainda pede autorização para o Fern na
    /// primeira vez que um dispositivo é usado.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard let tab, let window = tab.browserWindow else {
            decisionHandler(.deny)
            return
        }
        let devices: [CaptureDevice]
        switch type {
        case .camera: devices = [.camera]
        case .microphone: devices = [.microphone]
        case .cameraAndMicrophone: devices = [.camera, .microphone]
        @unknown default: devices = [.camera, .microphone]
        }
        let host = origin.host
        let store = window.sitePermissions
        let profile = tab.profileID

        switch store.decision(for: devices, host: host, profile: profile) {
        case .allow:
            decisionHandler(.grant)
        case .deny:
            decisionHandler(.deny)
        case .ask:
            tab.ask(
                PermissionRequest(host: host, devices: devices) { granted, remember in
                    if remember {
                        for device in devices {
                            store.set(granted ? .allow : .deny, for: device, host: host, profile: profile)
                        }
                    }
                    decisionHandler(granted ? .grant : .deny)
                })
        }
    }

    /// `<input type="file">`. Precisa do entitlement de arquivos escolhidos pelo usuário.
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let window = webView.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    // MARK: - Diálogos

    private static func makeAlert(message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        let host = frame.securityOrigin.host
        alert.messageText = host.isEmpty ? String(localized: "This page says:") : String(localized: "\(host) says:")
        alert.informativeText = message
        return alert
    }

    private func present(
        _ alert: NSAlert,
        over webView: WKWebView,
        completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void
    ) {
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}
