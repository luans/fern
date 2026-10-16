import AppKit
import Foundation
import Observation
import WebKit

/// Estado de uma aba. É dona do seu `WKWebView` e espelha as propriedades dele
/// (URL, título, progresso…) via KVO para a interface observar.
@MainActor
@Observable
final class Tab: Identifiable {
    enum SecurityState: Equatable {
        /// Página interna, em branco ou de outro esquema.
        case none
        /// HTTPS com todo o conteúdo seguro.
        case secure
        /// HTTP ou HTTPS com conteúdo misto.
        case insecure
    }

    struct LoadError: Equatable {
        let url: URL?
        let message: String
    }

    static let zoomLevels: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    let id = UUID()
    let profileID: Profile.ID
    let webView: WKWebView

    private(set) var url: URL?
    private(set) var title = ""
    private(set) var estimatedProgress = 0.0
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var hasOnlySecureContent = false
    private(set) var zoom: CGFloat = 1
    private(set) var loadError: LoadError?
    private(set) var favicon: NSImage?

    /// Câmera e microfone em uso pela página (ativos, pausados ou nenhum).
    private(set) var cameraCaptureState: WKMediaCaptureState = .none
    private(set) var microphoneCaptureState: WKMediaCaptureState = .none
    /// Se a página está fazendo som agora (ver `MediaObserver`).
    private(set) var isPlayingAudio = false
    /// Aba silenciada: os vídeos e áudios continuam tocando, mas sem som. Continua valendo
    /// ao navegar para outra página, como no Safari.
    private(set) var isAudioMuted = false
    /// O que cada frame com o script informou por último.
    @ObservationIgnored private var mediaFrames: [String: (info: WKFrameInfo, audible: Bool)] = [:]
    /// Pedido de câmera ou microfone esperando resposta na página.
    private(set) var pendingPermission: PermissionRequest?

    var isCapturing: Bool { cameraCaptureState != .none || microphoneCaptureState != .none }

    /// Onde a aba fica na barra lateral. A ordem dos casos é a ordem na lista de abas.
    enum Section: Int, Comparable, Sendable {
        /// Ícone na grade, no topo da barra lateral.
        case grid
        /// Card no topo do cartão de abas.
        case pinned
        /// Aba comum, que entra na sessão salva.
        case regular

        static func < (lhs: Section, rhs: Section) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private(set) var section: Section = .regular
    /// Endereço de uma aba da grade ou fixada no momento em que ela foi guardada. É o que
    /// volta quando o app abre de novo, mesmo que você tenha navegado depois.
    private(set) var savedURL: URL?

    var isInGrid: Bool { section == .grid }
    var isPinned: Bool { section == .pinned }
    /// Abas da grade e fixadas são salvas à parte e voltam sempre, mesmo sem restaurar a sessão.
    var isSaved: Bool { section != .regular }
    /// Página que a aba vai abrir na primeira vez em que for selecionada.
    private(set) var deferredURL: URL?

    /// Janela dona da aba. Usada para abrir links em novas abas.
    @ObservationIgnored weak var browserWindow: BrowserWindow?

    @ObservationIgnored private let navigationDelegate = NavigationDelegate()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var faviconTask: Task<Void, Never>?

    /// - Parameter configuration: passe a configuração recebida do WebKit quando a aba
    ///   nasce de um `target="_blank"`/`window.open`. `nil` cria uma configuração nova.
    /// - Parameters:
    ///   - profile: perfil cujos cookies e logins a aba usa.
    ///   - dataStore: armazenamento a usar no lugar do do perfil (janelas privadas).
    ///   - configuration: passe a configuração recebida do WebKit quando a aba nasce de
    ///     um `target="_blank"`/`window.open`. `nil` cria uma configuração nova.
    ///   - deferredURL: página que só carrega quando a aba for selecionada.
    init(
        profile: Profile.ID = Profile.defaultID,
        dataStore: WKWebsiteDataStore? = nil,
        engine: WebEngine = .shared,
        configuration: WKWebViewConfiguration? = nil,
        deferredURL: URL? = nil
    ) {
        profileID = profile
        webView = engine.makeWebView(
            configuration: configuration, dataStore: dataStore ?? engine.dataStore(for: profile))
        self.deferredURL = deferredURL
        navigationDelegate.tab = self
        webView.navigationDelegate = navigationDelegate
        webView.uiDelegate = navigationDelegate
        observeWebView()
        if let deferredURL {
            // Mostra o ícone do site antes de a página carregar.
            favicon = FaviconLoader.shared.cachedFavicon(for: deferredURL)
            faviconTask = Task { [weak self] in
                let icon = await FaviconLoader.shared.favicon(for: deferredURL, in: nil)
                guard let self, self.favicon == nil else { return }
                self.favicon = icon
            }
        }
    }

    /// Carrega a página adiada, se houver.
    func loadIfNeeded() {
        guard let deferredURL else { return }
        self.deferredURL = nil
        load(deferredURL)
    }

    func setSection(_ section: Section) {
        self.section = section
        savedURL = section == .regular ? nil : (savedURL ?? currentOrDeferredURL)
    }

    var currentOrDeferredURL: URL? {
        guard let url, url.absoluteString != "about:blank" else { return deferredURL }
        return url
    }

    // MARK: - Estado derivado

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = currentOrDeferredURL?.host(), !host.isEmpty { return host }
        return String(localized: "New Tab")
    }

    /// Texto exibido na barra de endereço quando ela não está em edição.
    var displayURL: String {
        currentOrDeferredURL?.absoluteString ?? ""
    }

    var securityState: SecurityState {
        switch url?.scheme?.lowercased() {
        case "https": hasOnlySecureContent ? .secure : .insecure
        case "http": .insecure
        default: .none
        }
    }

    var isBlank: Bool { displayURL.isEmpty && !isLoading && loadError == nil }
    var canZoomIn: Bool { zoom < (Self.zoomLevels.last ?? 1) - 0.001 }
    var canZoomOut: Bool { zoom > (Self.zoomLevels.first ?? 1) + 0.001 }

    // MARK: - Navegação

    func load(_ url: URL) {
        loadError = nil
        if WebEngine.canLoadInWebView(url) {
            webView.load(URLRequest(url: url))
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Para tudo antes de a aba sair da janela, para não sobrar áudio tocando.
    func close() {
        pendingPermission?.resolve(granted: false, remember: false)
        pendingPermission = nil
        webView.setCameraCaptureState(.none)
        webView.setMicrophoneCaptureState(.none)
        faviconTask?.cancel()
        webView.stopLoading()
        webView.pauseAllMediaPlayback()
        webView.removeFromSuperview()
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func stopLoading() { webView.stopLoading() }

    func reload() {
        if let failedURL = loadError?.url {
            load(failedURL)
        } else {
            webView.reload()
        }
    }

    func focusPage() {
        webView.window?.makeFirstResponder(webView)
    }

    // MARK: - Zoom

    func zoomIn() {
        if let next = Self.zoomLevels.first(where: { $0 > zoom + 0.001 }) { setZoom(next) }
    }

    func zoomOut() {
        if let previous = Self.zoomLevels.last(where: { $0 < zoom - 0.001 }) { setZoom(previous) }
    }

    func resetZoom() { setZoom(1) }

    private func setZoom(_ value: CGFloat) {
        webView.pageZoom = value
        zoom = value
    }

    // MARK: - Busca na página

    /// Seleciona a próxima ocorrência de `text` na página. Retorna se encontrou.
    func find(_ text: String, backwards: Bool = false) async -> Bool {
        guard !text.isEmpty else { return false }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        return (try? await webView.find(text, configuration: configuration))?.matchFound ?? false
    }

    // MARK: - Eventos do NavigationDelegate

    func navigationDidStart() {
        loadError = nil
        browserWindow?.tabDidStartNavigation(self)
        // A página antiga (e os frames dela) vai embora.
        mediaFrames = [:]
        isPlayingAudio = false
        // Um pedido da página anterior não vale para a nova.
        pendingPermission?.resolve(granted: false, remember: false)
        pendingPermission = nil
    }

    // MARK: - Câmera, microfone e mídia

    /// Mostra o pedido na página. Um pedido novo substitui (e nega) o anterior.
    func ask(_ request: PermissionRequest) {
        pendingPermission?.resolve(granted: false, remember: false)
        pendingPermission = request
    }

    func answerPermission(granted: Bool, remember: Bool) {
        pendingPermission?.resolve(granted: granted, remember: remember)
        pendingPermission = nil
    }

    /// Pausa ou retoma a câmera (a página continua achando que está em chamada).
    func toggleCameraMuted() {
        guard cameraCaptureState != .none else { return }
        webView.setCameraCaptureState(cameraCaptureState == .muted ? .active : .muted)
    }

    func toggleMicrophoneMuted() {
        guard microphoneCaptureState != .none else { return }
        webView.setMicrophoneCaptureState(microphoneCaptureState == .muted ? .active : .muted)
    }

    /// Desliga câmera e microfone da página.
    func stopCapture() {
        webView.setCameraCaptureState(.none)
        webView.setMicrophoneCaptureState(.none)
    }

    /// Silencia ou devolve o som de todos os frames da página.
    func toggleAudioMuted() {
        isAudioMuted.toggle()
        let script = "window.__fernMedia && window.__fernMedia.setMuted(\(isAudioMuted))"
        for (_, frame) in mediaFrames {
            webView.evaluateJavaScript(script, in: frame.info, in: .defaultClient) { _ in }
        }
    }

    /// Recebe o aviso de um frame e responde se a aba está silenciada.
    func mediaFrame(_ id: String, didReportAudible audible: Bool, frame: WKFrameInfo) -> Bool {
        mediaFrames[id] = (frame, audible)
        isPlayingAudio = mediaFrames.values.contains { $0.audible }
        return isAudioMuted
    }

    func navigationDidFinish() {
        browserWindow?.tabDidFinishLoading(self)
        guard let pageURL = webView.url else { return }
        faviconTask?.cancel()
        faviconTask = Task { [weak self] in
            let icon = await FaviconLoader.shared.favicon(for: pageURL, in: self?.webView)
            guard let self, !Task.isCancelled, self.webView.url?.host() == pageURL.host() else { return }
            self.favicon = icon
        }
    }

    func navigationDidFail(with error: Error) {
        let error = error as NSError
        // Cancelamentos (nova navegação, botão parar) e downloads interrompidos não são erros.
        let ignored =
            (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && [102, 204].contains(error.code))
        guard !ignored else { return }
        loadError = LoadError(
            url: error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? url,
            message: error.localizedDescription
        )
    }

    // MARK: - KVO

    private func observeWebView() {
        observations = [
            observe(\.url) { tab, webView in
                // Ao trocar de site, o ícone antigo deixa de valer.
                if tab.url?.host() != webView.url?.host() {
                    tab.favicon = FaviconLoader.shared.cachedFavicon(for: webView.url)
                }
                tab.url = webView.url
                tab.browserWindow?.tabDidNavigate()
            },
            observe(\.title) { tab, webView in
                tab.title = webView.title ?? ""
                tab.browserWindow?.tabTitleDidChange(tab)
            },
            observe(\.estimatedProgress) { $0.estimatedProgress = $1.estimatedProgress },
            observe(\.isLoading) { $0.isLoading = $1.isLoading },
            observe(\.canGoBack) { $0.canGoBack = $1.canGoBack },
            observe(\.canGoForward) { $0.canGoForward = $1.canGoForward },
            observe(\.hasOnlySecureContent) { $0.hasOnlySecureContent = $1.hasOnlySecureContent },
            observe(\.cameraCaptureState) { $0.cameraCaptureState = $1.cameraCaptureState },
            observe(\.microphoneCaptureState) { $0.microphoneCaptureState = $1.microphoneCaptureState },
        ]
    }

    private func observe<Value>(
        _ keyPath: KeyPath<WKWebView, Value>,
        update: @escaping @MainActor (Tab, WKWebView) -> Void
    ) -> NSKeyValueObservation {
        webView.observe(keyPath, options: [.initial, .new]) { [weak self] webView, _ in
            // O WKWebView sempre publica mudanças na thread principal.
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self, webView)
            }
        }
    }
}
