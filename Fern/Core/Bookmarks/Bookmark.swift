import Foundation
import SwiftData

/// Uma página salva nos Favoritos. Independente das abas: fechar a aba não apaga o
/// favorito. A ordem é a que você define arrastando na lista.
@Model
final class Bookmark {
    var profileID: UUID
    var urlString: String
    var title: String
    var createdAt: Date
    var order: Int

    init(profileID: UUID, urlString: String, title: String, createdAt: Date = .now, order: Int) {
        self.profileID = profileID
        self.urlString = urlString
        self.title = title
        self.createdAt = createdAt
        self.order = order
    }

    var url: URL? { URL(string: urlString) }

    var displayTitle: String {
        title.isEmpty ? (url?.host() ?? urlString) : title
    }
}
