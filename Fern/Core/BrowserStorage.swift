import Foundation

/// O que fica salvo por perfil em `UserDefaults`: grade, abas fixadas e a última
/// sessão (abas abertas), usada para continuar de onde parou.
struct BrowserStorage {
    static var standard: BrowserStorage { BrowserStorage(defaults: .standard) }

    struct Session: Codable, Equatable {
        var urls: [URL]
        /// Posição da aba ativa em `urls`, ou `nil` se a ativa era uma fixada.
        var activeIndex: Int?
    }

    let defaults: UserDefaults

    // MARK: - Grade e abas fixadas

    func savedURLs(_ section: Tab.Section, for profile: Profile.ID) -> [URL] {
        guard let key = savedKey(section, profile) else { return [] }
        return (defaults.stringArray(forKey: key) ?? []).compactMap(URL.init(string:))
    }

    func saveURLs(_ urls: [URL], _ section: Tab.Section, for profile: Profile.ID) {
        guard let key = savedKey(section, profile) else { return }
        defaults.set(urls.map(\.absoluteString), forKey: key)
    }

    // MARK: - Sessão

    func session(for profile: Profile.ID) -> Session? {
        defaults.data(forKey: sessionKey(profile)).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }

    func saveSession(_ session: Session, for profile: Profile.ID) {
        defaults.set(try? JSONEncoder().encode(session), forKey: sessionKey(profile))
    }

    func removeAll(for profile: Profile.ID) {
        for section in [Tab.Section.grid, .pinned] {
            if let key = savedKey(section, profile) { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: sessionKey(profile))
    }

    // MARK: - Chaves

    /// A grade usa a chave antiga "pinnedTabs": antes, a grade de ícones se chamava
    /// "abas fixadas". O perfil padrão mantém a chave de antes de existirem perfis.
    private func savedKey(_ section: Tab.Section, _ profile: Profile.ID) -> String? {
        let base: String
        switch section {
        case .grid: base = "pinnedTabs"
        case .pinned: base = "pinnedTabRows"
        case .regular: return nil
        }
        return profile == Profile.defaultID ? base : "\(base).\(profile.uuidString)"
    }

    private func sessionKey(_ profile: Profile.ID) -> String {
        "session.\(profile.uuidString)"
    }
}
