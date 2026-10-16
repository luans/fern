import Foundation
import Observation
import WebKit

/// Bloqueia anúncios e rastreadores com as regras de `Resources/blocklist.json`, no
/// formato dos bloqueadores de conteúdo do Safari. As regras são compiladas uma vez e
/// guardadas pelo `WKContentRuleListStore`; nas próximas execuções, só são carregadas.
/// Dá para desligar tudo nos Ajustes ou só em alguns sites.
@MainActor
@Observable
final class ContentBlocker {
    static let shared = ContentBlocker()

    /// Mude ao editar a lista, para o WebKit compilar de novo em vez de usar o cache.
    private static let ruleListIdentifier = "fern-blocklist-v1"
    private static let allowedHostsKey = "contentBlocker.allowedHosts"

    private(set) var ruleList: WKContentRuleList?
    /// Sites (sem "www.") em que o bloqueio está desligado.
    private(set) var allowedHosts: Set<String>

    @ObservationIgnored private let defaults: UserDefaults
    /// Se as regras estão aplicadas em cada `WKUserContentController`, para não refazer.
    @ObservationIgnored private var appliedState: [ObjectIdentifier: Bool] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        allowedHosts = Set(defaults.stringArray(forKey: Self.allowedHostsKey) ?? [])
    }

    var isEnabled: Bool { BrowserSettings.blocksContent }

    /// Carrega as regras do cache ou compila a lista do app. Chamado ao abrir o app.
    func prepare() async {
        guard ruleList == nil, let store = WKContentRuleListStore.default() else { return }
        if let cached = try? await store.contentRuleList(forIdentifier: Self.ruleListIdentifier) {
            ruleList = cached
            return
        }
        guard let url = Bundle.main.url(forResource: "blocklist", withExtension: "json"),
            let json = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        ruleList = try? await store.compileContentRuleList(
            forIdentifier: Self.ruleListIdentifier, encodedContentRuleList: json)
    }

    // MARK: - Por site

    static func normalizedHost(_ host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    func isBlocking(on url: URL?) -> Bool {
        guard isEnabled, ["http", "https"].contains(url?.scheme?.lowercased()) else { return false }
        guard let host = Self.normalizedHost(url?.host()) else { return true }
        return !allowedHosts.contains(host)
    }

    func setBlocking(_ blocking: Bool, on url: URL?) {
        guard let host = Self.normalizedHost(url?.host()) else { return }
        if blocking { allowedHosts.remove(host) } else { allowedHosts.insert(host) }
        defaults.set(allowedHosts.sorted(), forKey: Self.allowedHostsKey)
    }

    func removeException(_ host: String) {
        allowedHosts.remove(host)
        defaults.set(allowedHosts.sorted(), forKey: Self.allowedHostsKey)
    }

    // MARK: - Aplicar

    /// Liga ou desliga as regras no web view antes de carregar uma página principal.
    /// As regras valem para os carregamentos seguintes do web view.
    func apply(to webView: WKWebView, loading url: URL) {
        guard let ruleList else { return }
        let controller = webView.configuration.userContentController
        let shouldBlock = isBlocking(on: url)
        let key = ObjectIdentifier(controller)
        guard appliedState[key] != shouldBlock else { return }
        appliedState[key] = shouldBlock
        if shouldBlock {
            controller.add(ruleList)
        } else {
            controller.remove(ruleList)
        }
    }
}
