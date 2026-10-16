import Foundation

/// Um perfil é um contexto de navegação com cookies, logins e armazenamento próprios,
/// além das suas abas e abas fixadas. Ex.: "Pessoal" e "Trabalho" logados em contas
/// diferentes do mesmo site ao mesmo tempo.
struct Profile: Identifiable, Codable, Hashable, Sendable {
    /// O perfil padrão usa o armazenamento padrão do WebKit, então mantém os logins que
    /// já existiam antes de o Fern ter perfis.
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    let id: UUID
    var name: String
    var color: ProfileColor

    var isDefault: Bool { id == Self.defaultID }

    /// Primeira letra do nome, para o avatar.
    var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

enum ProfileColor: String, Codable, CaseIterable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, teal, gray
}
