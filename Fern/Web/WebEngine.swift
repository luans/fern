import Foundation
import WebKit

/// Único ponto que cria e configura `WKWebView`. Todo o resto do app conversa com o
/// WebKit através daqui ou de `Tab`, o que facilita trocar para a `WebView`/`WebPage`
/// do SwiftUI no futuro e aplicar regras de bloqueio e scripts num lugar só.
@MainActor
final class WebEngine {
    static let shared = WebEngine()

    /// Um armazenamento por perfil. Cada um tem seus cookies, logins, cache e
    /// armazenamento local, separados dos outros perfis.
    private var dataStores: [Profile.ID: WKWebsiteDataStore] = [:]

    /// - Parameters:
    ///   - configuration: a configuração que o WebKit entrega ao abrir uma nova janela
    ///     (`target="_blank"`). Ela já deriva da nossa (e do mesmo perfil) e precisa ser
    ///     usada sem cópia.
    ///   - dataStore: armazenamento de cookies e dados de sites (do perfil, ou em memória
    ///     numa janela privada).
    func makeWebView(configuration: WKWebViewConfiguration? = nil, dataStore: WKWebsiteDataStore) -> WKWebView {
        let webView = WKWebView(
            frame: .zero, configuration: configuration ?? makeConfiguration(dataStore: dataStore))
        MediaObserver.shared.install(in: webView.configuration.userContentController)
        DevToolsScript.install(in: webView.configuration.userContentController)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // Permite usar o Web Inspector do Safari (menu Desenvolvedor) nas páginas abertas.
        webView.isInspectable = true
        return webView
    }

    func dataStore(for profile: Profile.ID) -> WKWebsiteDataStore {
        if profile == Profile.defaultID { return .default() }
        if let store = dataStores[profile] { return store }
        let store = WKWebsiteDataStore(forIdentifier: profile)
        dataStores[profile] = store
        return store
    }

    /// Apaga do disco os dados de um perfil removido. O WebKit só deixa apagar quando
    /// nenhuma página usa mais o armazenamento, então espera as abas serem liberadas.
    func removeData(for profile: Profile.ID) {
        guard profile != Profile.defaultID else { return }
        dataStores[profile] = nil
        Task {
            for _ in 0..<5 {
                try? await Task.sleep(for: .seconds(1))
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: profile)
                    return
                } catch {
                    continue
                }
            }
        }
    }

    private func makeConfiguration(dataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = Self.applicationNameForUserAgent
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.allowsAirPlayForMediaPlayback = true
        switch BrowserSettings.autoplay {
        case .allowAll: configuration.mediaTypesRequiringUserActionForPlayback = []
        case .stopMediaWithSound: configuration.mediaTypesRequiringUserActionForPlayback = .audio
        case .never: configuration.mediaTypesRequiringUserActionForPlayback = .all
        }
        return configuration
    }

    /// Se o `WKWebView` sabe abrir esta URL. Esquemas como `mailto:` e `tel:` vão para
    /// o app padrão do sistema.
    static func canLoadInWebView(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return WKWebView.handlesURLScheme(scheme)
    }

    /// Sufixo do user agent no formato do Safari. Sem ele, alguns sites tratam o
    /// navegador como desconhecido e servem versões piores.
    private static let applicationNameForUserAgent: String = {
        let macOSMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        // Até o macOS 15, a versão do Safari era a do macOS + 3. A partir do 26, são iguais.
        let safariMajor = macOSMajor >= 26 ? macOSMajor : macOSMajor + 3
        return "Version/\(safariMajor).0 Safari/605.1.15"
    }()
}
