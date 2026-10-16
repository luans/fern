import Foundation

/// Preferências do usuário guardadas em `UserDefaults`. As views usam `@AppStorage`
/// com as mesmas chaves e os mesmos valores padrão.
enum BrowserSettings {
    enum Key {
        static let searchEngine = "searchEngine"
        static let restoresSession = "restoresSession"
        static let blocksContent = "blocksContent"
        static let autoplay = "autoplay"
    }

    static var searchEngine: SearchEngine {
        UserDefaults.standard.string(forKey: Key.searchEngine).flatMap(SearchEngine.init(rawValue:)) ?? .default
    }

    /// "Continuar de onde parou": reabre as abas da última vez. Ligado por padrão.
    static var restoresSession: Bool {
        UserDefaults.standard.object(forKey: Key.restoresSession) as? Bool ?? true
    }

    /// Bloquear anúncios e rastreadores. Ligado por padrão.
    static var blocksContent: Bool {
        UserDefaults.standard.object(forKey: Key.blocksContent) as? Bool ?? true
    }

    /// Reprodução automática de vídeo e áudio. Vale para as abas abertas depois da mudança.
    static var autoplay: AutoplayPolicy {
        UserDefaults.standard.string(forKey: Key.autoplay).flatMap(AutoplayPolicy.init(rawValue:)) ?? .default
    }
}

enum AutoplayPolicy: String, CaseIterable, Identifiable, Sendable {
    /// Tudo toca sozinho.
    case allowAll
    /// Vídeos sem som tocam sozinhos; com som, só depois de um clique. Padrão.
    case stopMediaWithSound
    /// Nada toca sozinho.
    case never

    static let `default`: AutoplayPolicy = .stopMediaWithSound

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .allowAll: "Allow All Auto-Play"
        case .stopMediaWithSound: "Stop Media with Sound"
        case .never: "Never Auto-Play"
        }
    }
}
