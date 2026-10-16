import SwiftUI

/// ★ na barra de endereço: salva a página nos Favoritos ou abre o balão para renomear
/// ou remover. Fica preenchida quando a página já é favorita.
struct BookmarkButton: View {
    let window: BrowserWindow
    let tab: Tab

    @State private var isEditing = false

    private var bookmarkable: Bool {
        ["http", "https"].contains(tab.url?.scheme?.lowercased())
    }

    var body: some View {
        if bookmarkable {
            let isBookmarked = window.bookmarks.isBookmarked(tab.url, profile: window.profileID)
            Button {
                if !isBookmarked { window.bookmarkActiveTab() }
                isEditing = true
            } label: {
                Image(systemName: isBookmarked ? "star.fill" : "star")
                    .foregroundStyle(isBookmarked ? Color.yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isBookmarked ? "Edit Bookmark" : "Add to Bookmarks")
            .accessibilityLabel(isBookmarked ? "Edit Bookmark" : "Add to Bookmarks")
            .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                if let bookmark = window.bookmarks.bookmark(for: tab.url, profile: window.profileID) {
                    BookmarkEditor(window: window, bookmark: bookmark) { isEditing = false }
                }
            }
            .onChange(of: window.bookmarkEditorRequest) { isEditing = true }
        }
    }
}

/// Balão para renomear ou remover um favorito.
private struct BookmarkEditor: View {
    let window: BrowserWindow
    let bookmark: Bookmark
    let done: () -> Void

    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bookmark")
                .font(.headline)
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Text(verbatim: bookmark.urlString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Button("Remove", role: .destructive) {
                    window.bookmarks.delete(bookmark)
                    done()
                }
                Spacer()
                Button("Done", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { title = bookmark.title }
    }

    private func save() {
        window.bookmarks.rename(bookmark, to: title)
        done()
    }
}

/// Lista de Favoritos do perfil (⌥⌘B): busca, abrir, renomear, reordenar e apagar.
struct BookmarksView: View {
    let window: BrowserWindow

    @State private var query = ""
    @State private var renaming: Bookmark?
    @Environment(\.dismiss) private var dismiss

    private var store: BookmarkStore { window.bookmarks }

    private var bookmarks: [Bookmark] {
        _ = store.revision
        return store.bookmarks(profile: window.profileID, matching: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Bookmarks")
                    .font(.title3.weight(.semibold))
                Spacer()
                TextField("Search Bookmarks", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            if bookmarks.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Bookmarks" : "No Results",
                    systemImage: "star",
                    description: Text("Press ⌘D or click the star in the address bar to save a page.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(bookmarks) { bookmark in
                        BookmarkRow(
                            bookmark: bookmark,
                            isRenaming: renaming?.id == bookmark.id,
                            rename: { title in rename(bookmark, to: title) },
                            open: { inNewTab in open(bookmark, inNewTab: inNewTab) }
                        )
                        .contextMenu {
                            Button("Open") { open(bookmark) }
                            Button("Open in New Tab") { open(bookmark, inNewTab: true) }
                            Divider()
                            Button("Rename") { renaming = bookmark }
                            Button("Copy Link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(bookmark.urlString, forType: .string)
                            }
                            Divider()
                            Button("Delete") { store.delete(bookmark) }
                        }
                    }
                    .onMove(perform: moveHandler)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 620, height: 520)
    }

    private func rename(_ bookmark: Bookmark, to title: String) {
        store.rename(bookmark, to: title)
        renaming = nil
    }

    private func open(_ bookmark: Bookmark, inNewTab: Bool = false) {
        window.open(bookmark, inNewTab: inNewTab)
        dismiss()
    }

    /// Reordenar só faz sentido com a lista completa, sem busca.
    private var moveHandler: ((IndexSet, Int) -> Void)? {
        guard query.isEmpty else { return nil }
        let store = store
        let profile = window.profileID
        return { source, destination in
            store.move(profile: profile, fromOffsets: source, toOffset: destination)
        }
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    let isRenaming: Bool
    let rename: (String) -> Void
    let open: (_ inNewTab: Bool) -> Void

    @State private var title = ""
    @State private var favicon: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let favicon {
                    Image(nsImage: favicon).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "star").foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)

            if isRenaming {
                TextField("Name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { rename(title) }
                    .onAppear { title = bookmark.title }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: bookmark.displayTitle)
                        .lineLimit(1)
                    Text(verbatim: bookmark.url?.host() ?? bookmark.urlString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else { return }
            open(NSEvent.modifierFlags.contains(.command))
        }
        .help(bookmark.urlString)
        .task(id: bookmark.urlString) {
            guard let url = bookmark.url else { return }
            favicon = FaviconLoader.shared.cachedFavicon(for: url)
            if favicon == nil { favicon = await FaviconLoader.shared.favicon(for: url, in: nil) }
        }
    }
}
