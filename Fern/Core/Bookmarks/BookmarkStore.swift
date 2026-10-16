import Foundation
import Observation
import SwiftData

/// Favoritos de cada perfil, salvos com SwiftData.
@MainActor
@Observable
final class BookmarkStore {
    static let shared = BookmarkStore()

    /// Muda a cada alteração, para as telas que listam os favoritos se atualizarem.
    private(set) var revision = 0

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var context: ModelContext { container.mainContext }

    /// - Parameter inMemory: `true` nos testes, para não tocar nos favoritos de verdade.
    init(inMemory: Bool = false) {
        let configuration = ModelConfiguration("Bookmarks", isStoredInMemoryOnly: inMemory)
        if let container = try? ModelContainer(for: Bookmark.self, configurations: configuration) {
            self.container = container
        } else {
            let fallback = ModelConfiguration("Bookmarks", isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(for: Bookmark.self, configurations: fallback)
            } catch {
                fatalError("Não foi possível criar os favoritos em memória: \(error)")
            }
        }
    }

    // MARK: - Ler

    /// Favoritos do perfil na ordem da lista, filtrados pelo texto.
    func bookmarks(profile: UUID, matching query: String = "") -> [Bookmark] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let predicate: Predicate<Bookmark> =
            query.isEmpty
            ? #Predicate { $0.profileID == profile }
            : #Predicate {
                $0.profileID == profile
                    && ($0.title.localizedStandardContains(query) || $0.urlString.localizedStandardContains(query))
            }
        let descriptor = FetchDescriptor<Bookmark>(predicate: predicate, sortBy: [SortDescriptor(\.order)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func bookmark(for url: URL?, profile: UUID) -> Bookmark? {
        guard let urlString = url?.absoluteString else { return nil }
        var descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.profileID == profile && $0.urlString == urlString })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func isBookmarked(_ url: URL?, profile: UUID) -> Bool {
        _ = revision
        return bookmark(for: url, profile: profile) != nil
    }

    /// Sugestões para a barra de endereço, na ordem da lista.
    func suggestions(for query: String, profile: UUID, limit: Int = 3) -> [Bookmark] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return Array(bookmarks(profile: profile, matching: query).prefix(limit))
    }

    // MARK: - Alterar

    /// Salva a página no fim da lista. Se já for favorita, devolve o favorito existente.
    @discardableResult
    func add(url: URL, title: String, profile: UUID) -> Bookmark {
        if let existing = bookmark(for: url, profile: profile) { return existing }
        let order = (bookmarks(profile: profile).last?.order ?? -1) + 1
        let bookmark = Bookmark(profileID: profile, urlString: url.absoluteString, title: title, order: order)
        context.insert(bookmark)
        save()
        return bookmark
    }

    func rename(_ bookmark: Bookmark, to title: String) {
        bookmark.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func delete(_ bookmark: Bookmark) {
        context.delete(bookmark)
        save()
    }

    /// Reordena arrastando na lista (os índices são os da lista sem filtro).
    func move(profile: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = bookmarks(profile: profile)
        list.move(fromOffsets: source, toOffset: destination)
        for (index, bookmark) in list.enumerated() where bookmark.order != index {
            bookmark.order = index
        }
        save()
    }

    func removeAll(profile: UUID) {
        try? context.delete(model: Bookmark.self, where: #Predicate { $0.profileID == profile })
        save()
    }

    private func save() {
        try? context.save()
        revision += 1
    }
}
