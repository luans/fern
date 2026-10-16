import Foundation

/// Buscadores oferecidos nas configurações. O padrão é o DuckDuckGo.
enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
    case duckDuckGo
    case google
    case bing
    case brave
    case ecosia

    static let `default`: SearchEngine = .duckDuckGo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .brave: "Brave Search"
        case .ecosia: "Ecosia"
        }
    }

    private var endpoint: String {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/"
        case .google: "https://www.google.com/search"
        case .bing: "https://www.bing.com/search"
        case .brave: "https://search.brave.com/search"
        case .ecosia: "https://www.ecosia.org/search"
        }
    }

    /// Monta a URL de busca. Caracteres como `+`, `&` e `=` são codificados para não
    /// mudarem o sentido da query (ex.: "c++" não pode virar "c  ").
    func searchURL(for query: String) -> URL {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .searchTermAllowed) ?? query
        guard var components = URLComponents(string: endpoint) else {
            preconditionFailure("Endpoint inválido para \(self)")
        }
        components.percentEncodedQuery = "q=\(encoded)"
        guard let url = components.url else {
            preconditionFailure("Não foi possível montar a URL de busca para \(self)")
        }
        return url
    }
}

extension CharacterSet {
    /// Caracteres que podem ir sem codificação dentro do valor de um parâmetro de busca.
    fileprivate static let searchTermAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=#?/")
        return set
    }()
}
