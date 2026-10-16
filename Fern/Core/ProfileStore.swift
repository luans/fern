import Foundation
import Observation

/// Lista de perfis, compartilhada por todas as janelas e salva em `UserDefaults`.
@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore(defaults: .standard)

    /// Postada quando um perfil é apagado. `object` é o `Profile.ID`. As janelas fecham
    /// as abas desse perfil antes de os dados dele serem removidos do disco.
    static let didDeleteProfile = Notification.Name("FernProfileStoreDidDeleteProfile")

    private enum Key {
        static let profiles = "profiles"
        static let lastUsedProfileID = "lastUsedProfileID"
    }

    /// Perfis salvos.
    private var saved: [Profile]
    /// Perfil criado pelo gesto de troca quando não há próximo perfil. Só vira um perfil
    /// de verdade (salvo) quando uma página é aberta nele ou quando é renomeado; se você
    /// sair dele sem usar, ele é descartado.
    private(set) var draft: Profile?
    @ObservationIgnored private let defaults: UserDefaults

    /// Perfis salvos e, por último, o rascunho, se houver.
    var profiles: [Profile] { saved + (draft.map { [$0] } ?? []) }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Key.profiles).flatMap { try? JSONDecoder().decode([Profile].self, from: $0) }
        var profiles = saved ?? []
        if !profiles.contains(where: \.isDefault) {
            profiles.insert(
                Profile(id: Profile.defaultID, name: String(localized: "Personal"), color: .blue), at: 0)
        }
        self.saved = profiles
    }

    func profile(_ id: Profile.ID) -> Profile? {
        profiles.first { $0.id == id }
    }

    /// Perfil usado por último; novas janelas abrem nele.
    var lastUsedProfileID: Profile.ID {
        get {
            defaults.string(forKey: Key.lastUsedProfileID).flatMap(UUID.init(uuidString:))
                .flatMap { profile($0)?.id } ?? Profile.defaultID
        }
        set { defaults.set(newValue.uuidString, forKey: Key.lastUsedProfileID) }
    }

    @discardableResult
    func add(name: String, color: ProfileColor) -> Profile {
        let profile = Profile(id: UUID(), name: Self.cleanName(name), color: color)
        saved.append(profile)
        save()
        return profile
    }

    func update(_ id: Profile.ID, name: String? = nil, color: ProfileColor? = nil) {
        if isDraft(id) { commitDraft(id) }
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        if let name { saved[index].name = Self.cleanName(name) }
        if let color { saved[index].color = color }
        save()
    }

    // MARK: - Rascunho

    func isDraft(_ id: Profile.ID) -> Bool {
        draft?.id == id
    }

    /// Cria (ou devolve) o perfil rascunho, numa cor que ainda não está em uso.
    func createDraft() -> Profile {
        if let draft { return draft }
        let usedColors = Set(saved.map(\.color))
        let color = ProfileColor.allCases.first { !usedColors.contains($0) } ?? .gray
        let profile = Profile(id: UUID(), name: String(localized: "New Profile"), color: color)
        draft = profile
        return profile
    }

    /// Transforma o rascunho num perfil salvo.
    func commitDraft(_ id: Profile.ID) {
        guard let draft, draft.id == id else { return }
        saved.append(draft)
        self.draft = nil
        save()
    }

    /// Apaga o perfil e, depois que as janelas fecharem as abas dele, os seus dados
    /// (cookies, logins, cache). O perfil padrão não pode ser apagado.
    func delete(_ id: Profile.ID) {
        guard id != Profile.defaultID else { return }
        if isDraft(id) {
            draft = nil
        } else {
            guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
            saved.remove(at: index)
            save()
        }
        BrowserStorage(defaults: defaults).removeAll(for: id)
        HistoryStore.shared.clear(profile: id, since: nil)
        SitePermissionStore.shared.removeAll(profile: id)
        BookmarkStore.shared.removeAll(profile: id)
        if lastUsedProfileID == id { lastUsedProfileID = Profile.defaultID }
        NotificationCenter.default.post(name: Self.didDeleteProfile, object: id)
        WebEngine.shared.removeData(for: id)
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(saved), forKey: Key.profiles)
    }

    private static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Profile") : String(trimmed.prefix(30))
    }
}
