import Foundation

/// Uma sugestão da barra de endereço: uma aba já aberta (vai para ela), um favorito ou
/// uma página do histórico (os dois abrem na aba atual).
struct AddressSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case openTab(Tab.ID)
        case bookmark
        case history
    }

    let title: String
    let url: URL
    let kind: Kind

    var id: String {
        switch kind {
        case .openTab(let tabID): "tab-\(tabID.uuidString)"
        case .bookmark: "bookmark-\(url.absoluteString)"
        case .history: "history-\(url.absoluteString)"
        }
    }
}

extension BrowserWindow {
    /// Abas abertas que combinam com o texto (as da grade e as fixadas primeiro), depois
    /// favoritos e, por fim, páginas do histórico. Cada endereço aparece uma vez só.
    func suggestions(for text: String, limit: Int = 8) -> [AddressSuggestion] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        var suggestions: [AddressSuggestion] = []
        var seenURLs: Set<String> = []

        let openTabs = tabs.filter { $0.id != activeTabID }.sorted { $0.section < $1.section }
        for tab in openTabs {
            guard let url = tab.currentOrDeferredURL,
                tab.displayTitle.localizedStandardContains(query) || url.absoluteString.localizedStandardContains(query)
            else { continue }
            suggestions.append(AddressSuggestion(title: tab.displayTitle, url: url, kind: .openTab(tab.id)))
            seenURLs.insert(url.absoluteString)
            if suggestions.count == 3 { break }
        }

        for bookmark in bookmarks.suggestions(for: query, profile: profileID) {
            guard let url = bookmark.url, seenURLs.insert(url.absoluteString).inserted else { continue }
            suggestions.append(AddressSuggestion(title: bookmark.displayTitle, url: url, kind: .bookmark))
        }

        for entry in history.suggestions(for: query, profile: profileID, limit: limit) {
            guard let url = entry.url, seenURLs.insert(url.absoluteString).inserted else { continue }
            suggestions.append(AddressSuggestion(title: entry.displayTitle, url: url, kind: .history))
            if suggestions.count == limit { break }
        }
        return suggestions
    }

    func open(_ suggestion: AddressSuggestion) {
        switch suggestion.kind {
        case .openTab(let id):
            select(id)
        case .bookmark, .history:
            activeTab.load(suggestion.url)
            activeTab.focusPage()
        }
    }
}
