import Foundation
import Testing

@testable import Fern

@MainActor
struct BookmarkStoreTests {
    let profile = UUID()

    @Test func addsAtTheEndAndIgnoresDuplicates() {
        let store = BookmarkStore(inMemory: true)
        store.add(url: URL(string: "https://a.example")!, title: "A", profile: profile)
        store.add(url: URL(string: "https://b.example")!, title: "B", profile: profile)
        store.add(url: URL(string: "https://a.example")!, title: "A again", profile: profile)

        #expect(store.bookmarks(profile: profile).map(\.title) == ["A", "B"])
        #expect(store.isBookmarked(URL(string: "https://a.example")!, profile: profile))
    }

    @Test func eachProfileHasItsOwnBookmarks() {
        let store = BookmarkStore(inMemory: true)
        store.add(url: URL(string: "https://a.example")!, title: "A", profile: profile)
        #expect(store.bookmarks(profile: UUID()).isEmpty)
    }

    @Test func renamesAndDeletes() throws {
        let store = BookmarkStore(inMemory: true)
        let bookmark = store.add(url: URL(string: "https://a.example")!, title: "A", profile: profile)
        store.rename(bookmark, to: "  Site A  ")
        #expect(store.bookmarks(profile: profile).first?.title == "Site A")

        store.delete(bookmark)
        #expect(store.bookmarks(profile: profile).isEmpty)
    }

    @Test func reordersByDragging() {
        let store = BookmarkStore(inMemory: true)
        for name in ["A", "B", "C"] {
            store.add(url: URL(string: "https://\(name.lowercased()).example")!, title: name, profile: profile)
        }
        store.move(profile: profile, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.bookmarks(profile: profile).map(\.title) == ["C", "A", "B"])
    }

    @Test func searchesTitlesAndAddresses() {
        let store = BookmarkStore(inMemory: true)
        store.add(url: URL(string: "https://swift.org")!, title: "Swift", profile: profile)
        store.add(url: URL(string: "https://webkit.org")!, title: "Motor", profile: profile)
        #expect(store.bookmarks(profile: profile, matching: "webkit").map(\.title) == ["Motor"])
    }

    @Test func bookmarkingTheActiveTabUsesItsPage() {
        let store = BookmarkStore(inMemory: true)
        let window = BrowserWindow(
            profiles: ProfileStore(defaults: UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!),
            history: HistoryStore(inMemory: true),
            bookmarks: store,
            storage: BrowserStorage(defaults: UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!),
            restoresSession: false,
            restoreTracker: SessionRestoreTracker()
        )
        window.activeTab.load(URL(string: "https://example.com/page")!)
        window.bookmarkActiveTab()
        #expect(store.bookmarks(profile: window.profileID).map(\.urlString) == ["https://example.com/page"])
    }

    @Test func blankPagesCannotBeBookmarked() {
        let store = BookmarkStore(inMemory: true)
        let window = BrowserWindow(
            profiles: ProfileStore(defaults: UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!),
            history: HistoryStore(inMemory: true),
            bookmarks: store,
            storage: BrowserStorage(defaults: UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!),
            restoresSession: false,
            restoreTracker: SessionRestoreTracker()
        )
        window.bookmarkActiveTab()
        #expect(store.bookmarks(profile: window.profileID).isEmpty)
    }
}
