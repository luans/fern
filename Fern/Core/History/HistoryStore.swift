import Foundation
import Observation
import SwiftData

/// Histórico de navegação, salvo com SwiftData. Cada perfil tem o seu; janelas privadas
/// não gravam nada.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    /// Muda a cada alteração, para as telas que listam o histórico se atualizarem.
    private(set) var revision = 0

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var context: ModelContext { container.mainContext }

    /// - Parameter inMemory: `true` nos testes, para não tocar no histórico de verdade.
    init(inMemory: Bool = false) {
        let configuration = ModelConfiguration("History", isStoredInMemoryOnly: inMemory)
        if let container = try? ModelContainer(for: HistoryEntry.self, configurations: configuration) {
            self.container = container
        } else {
            // Sem conseguir abrir o arquivo (ex.: formato incompatível), o histórico desta
            // execução fica só na memória em vez de o app não abrir.
            let fallback = ModelConfiguration("History", isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(for: HistoryEntry.self, configurations: fallback)
            } catch {
                fatalError("Não foi possível criar o histórico em memória: \(error)")
            }
        }
    }

    // MARK: - Gravar

    /// Registra uma visita. Só páginas da web (http e https) entram no histórico.
    func recordVisit(url: URL, title: String, profile: UUID, at date: Date = .now) {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        if let entry = entry(for: url, profile: profile) {
            entry.lastVisited = date
            entry.visitCount += 1
            if !title.isEmpty { entry.title = title }
        } else {
            context.insert(
                HistoryEntry(profileID: profile, urlString: url.absoluteString, title: title, lastVisited: date))
        }
        save()
    }

    /// O título costuma chegar depois de a página terminar de carregar.
    func updateTitle(_ title: String, for url: URL, profile: UUID) {
        guard !title.isEmpty, let entry = entry(for: url, profile: profile), entry.title != title else { return }
        entry.title = title
        save()
    }

    // MARK: - Ler

    /// Entradas do perfil, das mais recentes para as mais antigas, filtradas pelo texto.
    func entries(profile: UUID, matching query: String = "", limit: Int? = nil) -> [HistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: predicate(profile: profile, query: query),
            sortBy: [SortDescriptor(\.lastVisited, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Sugestões para a barra de endereço: as mais visitadas primeiro, depois as recentes.
    func suggestions(for query: String, profile: UUID, limit: Int = 6) -> [HistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: predicate(profile: profile, query: query),
            sortBy: [SortDescriptor(\.visitCount, order: .reverse), SortDescriptor(\.lastVisited, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Apagar

    func delete(_ entry: HistoryEntry) {
        context.delete(entry)
        save()
    }

    /// Apaga o histórico do perfil a partir de `since` (`nil` apaga tudo).
    func clear(profile: UUID, since: Date?) {
        let start = since ?? .distantPast
        try? context.delete(
            model: HistoryEntry.self,
            where: #Predicate { $0.profileID == profile && $0.lastVisited >= start }
        )
        save()
    }

    // MARK: - Interno

    private func entry(for url: URL, profile: UUID) -> HistoryEntry? {
        let urlString = url.absoluteString
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.profileID == profile && $0.urlString == urlString })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func predicate(profile: UUID, query: String) -> Predicate<HistoryEntry> {
        if query.isEmpty {
            return #Predicate { $0.profileID == profile }
        }
        return #Predicate {
            $0.profileID == profile
                && ($0.urlString.localizedStandardContains(query) || $0.title.localizedStandardContains(query))
        }
    }

    private func save() {
        try? context.save()
        revision += 1
    }
}
