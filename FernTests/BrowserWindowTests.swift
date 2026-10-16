import Foundation
import Testing

@testable import Fern

/// Janela com armazenamento só do teste (`UserDefaults` próprio), para não misturar com
/// os perfis, abas fixadas e sessões de verdade do app.
@MainActor
private func makeWindow(
    pinned: [URL] = [],
    defaults: UserDefaults = UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!,
    restoresSession: Bool = false,
    isPrivate: Bool = false,
    history: HistoryStore = HistoryStore(inMemory: true),
    bookmarks: BookmarkStore = BookmarkStore(inMemory: true)
) -> BrowserWindow {
    let storage = BrowserStorage(defaults: defaults)
    if !pinned.isEmpty { storage.saveURLs(pinned, .pinned, for: Profile.defaultID) }
    return BrowserWindow(
        isPrivate: isPrivate,
        profiles: ProfileStore(defaults: defaults),
        history: history,
        bookmarks: bookmarks,
        storage: storage,
        restoresSession: restoresSession,
        restoreTracker: SessionRestoreTracker()
    )
}

@MainActor
struct BrowserWindowTests {
    @Test func startsWithOneBlankTab() {
        let window = makeWindow()
        #expect(window.tabs.count == 1)
        #expect(window.activeTab.isBlank)
        #expect(window.activeTab.browserWindow === window)
    }

    @Test func newTabOpensRightAfterTheActiveOneAndActivates() {
        let window = makeWindow()
        let first = window.activeTab
        let third = window.newTab()
        window.select(first.id)
        let second = window.newTab()

        #expect(window.tabs.map(\.id) == [first.id, second.id, third.id])
        #expect(window.activeTabID == second.id)
    }

    @Test func backgroundTabDoesNotChangeTheActiveTab() {
        let window = makeWindow()
        let first = window.activeTab
        window.newTab(activate: false)
        #expect(window.tabs.count == 2)
        #expect(window.activeTabID == first.id)
    }

    @Test func closingTheActiveTabSelectsTheOneBelow() {
        let window = makeWindow()
        let first = window.activeTab
        let second = window.newTab()
        let third = window.newTab()
        window.select(second.id)

        #expect(window.closeTab(second.id))
        #expect(window.tabs.map(\.id) == [first.id, third.id])
        #expect(window.activeTabID == third.id)
    }

    @Test func closingTheLastTabInTheListSelectsTheOneAbove() {
        let window = makeWindow()
        let first = window.activeTab
        let second = window.newTab()

        #expect(window.closeTab(second.id))
        #expect(window.activeTabID == first.id)
    }

    @Test func closingABackgroundTabKeepsTheActiveTab() {
        let window = makeWindow()
        let first = window.activeTab
        let second = window.newTab()
        window.select(first.id)

        window.closeTab(second.id)
        #expect(window.activeTabID == first.id)
    }

    @Test func theOnlyTabCannotBeClosed() {
        let window = makeWindow()
        #expect(!window.closeTab(window.activeTabID))
        #expect(window.tabs.count == 1)
    }

    @Test func reopensTheLastClosedTabAtItsPosition() throws {
        let window = makeWindow()
        let url = try #require(URL(string: "data:text/html,reopen"))
        let first = window.activeTab
        let closed = window.newTab(url: url)
        window.newTab()
        #expect(!window.canReopenClosedTab)

        window.closeTab(closed.id)
        #expect(window.canReopenClosedTab)

        window.reopenClosedTab()
        #expect(window.tabs.count == 3)
        #expect(window.tabs[1].id == window.activeTabID)
        #expect(window.activeTab.url == url)
        #expect(window.tabs[0].id == first.id)
        #expect(!window.canReopenClosedTab)
    }

    @Test func blankTabsAreNotRemembered() {
        let window = makeWindow()
        let blank = window.newTab()
        window.closeTab(blank.id)
        #expect(!window.canReopenClosedTab)
    }

    @Test(arguments: [(1, 0), (3, 2), (5, 4), (9, 4)])
    func selectsTabByNumber(_ number: Int, _ expectedIndex: Int) {
        let window = makeWindow()
        for _ in 0..<4 { window.newTab() }
        window.selectTab(number: number)
        #expect(window.activeTabID == window.tabs[expectedIndex].id)
    }

    @Test func numberBeyondTheTabCountDoesNothing() {
        let window = makeWindow()
        window.newTab()
        let active = window.activeTabID
        window.selectTab(number: 5)
        #expect(window.activeTabID == active)
    }

    @Test func nextAndPreviousWrapAround() {
        let window = makeWindow()
        let first = window.activeTab
        window.newTab()
        let last = window.newTab()

        window.selectNextTab()
        #expect(window.activeTabID == first.id)
        window.selectPreviousTab()
        #expect(window.activeTabID == last.id)
    }

    @Test func closeOtherTabsKeepsOnlyTheChosenOne() {
        let window = makeWindow()
        let keep = window.newTab()
        window.newTab()
        window.closeOtherTabs(than: keep.id)
        #expect(window.tabs.map(\.id) == [keep.id])
        #expect(window.activeTabID == keep.id)
    }

    @Test func movesTabs() {
        let window = makeWindow()
        let first = window.activeTab
        let second = window.newTab()
        let third = window.newTab()
        window.moveTabs(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(window.tabs.map(\.id) == [third.id, first.id, second.id])
    }

    @Test func dragsATabOntoAnother() {
        let window = makeWindow()
        let first = window.activeTab
        let second = window.newTab()
        let third = window.newTab()
        window.moveTab(first.id, to: third.id)
        #expect(window.tabs.map(\.id) == [second.id, third.id, first.id])
        window.moveTab(first.id, to: second.id)
        #expect(window.tabs.map(\.id) == [first.id, second.id, third.id])
    }

    // MARK: - Abas fixadas

    @Test func pinningMovesTheTabToThePinnedSection() throws {
        let window = makeWindow()
        let first = window.activeTab
        let page = window.newTab(url: URL(string: "https://example.com")!)
        window.togglePin(page.id)

        #expect(page.isPinned)
        #expect(window.pinnedTabs.map(\.id) == [page.id])
        #expect(window.tabs.map(\.id) == [page.id, first.id])
    }

    @Test func blankTabsCannotBePinned() {
        let window = makeWindow()
        window.togglePin(window.activeTabID)
        #expect(window.pinnedTabs.isEmpty)
    }

    @Test func unpinningMovesTheTabToTheTopOfTheOthers() throws {
        let window = makeWindow()
        let page = window.newTab(url: URL(string: "https://example.com")!)
        window.togglePin(page.id)
        window.togglePin(page.id)
        #expect(!page.isPinned)
        #expect(window.tabs.first?.id == page.id)
    }

    @Test func pinnedTabsAreRestoredWithoutLoading() throws {
        let url = try #require(URL(string: "https://example.com/inbox"))
        let window = makeWindow(pinned: [url])

        #expect(window.tabs.count == 2)
        let pinned = try #require(window.pinnedTabs.first)
        #expect(pinned.deferredURL == url)
        #expect(pinned.url == nil)
        #expect(!window.activeTab.isPinned)

        window.select(pinned.id)
        #expect(pinned.deferredURL == nil)
    }

    @Test func newTabsNeverGoInsideThePinnedSection() throws {
        let url = try #require(URL(string: "https://example.com"))
        let window = makeWindow(pinned: [url, url])
        window.select(window.tabs[0].id)
        let tab = window.newTab()
        #expect(window.tabs.firstIndex { $0.id == tab.id } == 2)
    }

    @Test func droppingOntoAPinnedTabPinsAndDroppingOntoAnotherUnpins() throws {
        let url = try #require(URL(string: "https://example.com"))
        let window = makeWindow(pinned: [url])
        let pinned = window.tabs[0]
        let page = window.newTab(url: URL(string: "https://example.org")!)

        window.moveTab(page.id, to: pinned.id)
        #expect(page.isPinned)
        #expect(window.tabs.prefix(2).map(\.id) == [page.id, pinned.id])

        let other = window.regularTabs[0]
        window.moveTab(page.id, to: other.id)
        #expect(!page.isPinned)
    }

    // MARK: - Sessão

    @Test func continuesWhereItLeftOff() throws {
        let defaults = UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!
        let first = makeWindow(defaults: defaults)
        first.activeTab.load(URL(string: "https://example.com/a")!)
        first.newTab(url: URL(string: "https://example.com/b")!)
        first.newTab(url: URL(string: "https://example.com/c")!)
        first.selectTab(number: 2)
        first.saveSessionNow()

        let restored = makeWindow(defaults: defaults, restoresSession: true)
        #expect(
            restored.tabs.map(\.displayURL) == [
                "https://example.com/a", "https://example.com/b", "https://example.com/c",
            ])
        #expect(restored.activeTab.displayURL == "https://example.com/b")
        // Só a aba ativa carrega; as outras esperam ser abertas.
        #expect(restored.activeTab.deferredURL == nil)
        #expect(restored.tabs[0].deferredURL != nil)
    }

    @Test func startsFreshWhenRestoringIsOff() {
        let defaults = UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!
        let first = makeWindow(defaults: defaults)
        first.newTab(url: URL(string: "https://example.com")!)
        first.saveSessionNow()

        let window = makeWindow(defaults: defaults, restoresSession: false)
        #expect(window.tabs.count == 1)
        #expect(window.activeTab.isBlank)
    }

    // MARK: - Perfis

    @Test func eachProfileHasItsOwnTabs() {
        let window = makeWindow()
        window.activeTab.load(URL(string: "https://example.com/personal")!)
        let personalTabs = window.tabs.map(\.id)

        let work = window.profiles.add(name: "Work", color: .orange)
        window.switchProfile(to: work.id)
        #expect(window.profileID == work.id)
        #expect(window.tabs.count == 1)
        #expect(window.activeTab.isBlank)
        #expect(window.activeTab.profileID == work.id)

        window.switchProfile(to: Profile.defaultID)
        #expect(window.tabs.map(\.id) == personalTabs)
    }

    @Test func deletingTheActiveProfileGoesBackToTheDefault() {
        let window = makeWindow()
        let work = window.profiles.add(name: "Work", color: .orange)
        window.switchProfile(to: work.id)

        window.profiles.delete(work.id)
        #expect(window.profileID == Profile.defaultID)
        #expect(window.profiles.profile(work.id) == nil)
    }

    @Test func theDefaultProfileCannotBeDeleted() {
        let window = makeWindow()
        window.profiles.delete(Profile.defaultID)
        #expect(window.profiles.profile(Profile.defaultID) != nil)
    }

    // MARK: - Grade

    @Test func gridComesBeforePinnedTabs() {
        let window = makeWindow()
        let pinned = window.newTab(url: URL(string: "https://example.com/pinned")!)
        let gridTab = window.newTab(url: URL(string: "https://example.com/grid")!)
        window.togglePin(pinned.id)
        window.toggleGrid(gridTab.id)

        #expect(window.gridTabs.map(\.id) == [gridTab.id])
        #expect(window.pinnedTabs.map(\.id) == [pinned.id])
        #expect(window.tabs.prefix(2).map(\.id) == [gridTab.id, pinned.id])
    }

    @Test func gridAndPinnedTabsComeBackSeparately() {
        let defaults = UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!
        let first = makeWindow(defaults: defaults)
        let pinned = first.newTab(url: URL(string: "https://example.com/pinned")!)
        let gridTab = first.newTab(url: URL(string: "https://example.com/grid")!)
        first.togglePin(pinned.id)
        first.toggleGrid(gridTab.id)

        let window = makeWindow(defaults: defaults)
        #expect(window.gridTabs.map(\.displayURL) == ["https://example.com/grid"])
        #expect(window.pinnedTabs.map(\.displayURL) == ["https://example.com/pinned"])
    }

    // MARK: - Perfil rascunho

    @Test func swipingPastTheLastProfileCreatesADraft() {
        let window = makeWindow()
        window.switchToNextProfile()

        #expect(window.profiles.isDraft(window.profileID))
        #expect(window.profiles.profiles.count == 2)

        // Mais um gesto no rascunho não cria outro.
        window.switchToNextProfile()
        #expect(window.profiles.profiles.count == 2)
    }

    @Test func leavingAnUnusedDraftDiscardsIt() {
        let window = makeWindow()
        window.switchToNextProfile()
        let draft = window.profileID

        window.switchToPreviousProfile()
        #expect(window.profileID == Profile.defaultID)
        #expect(window.profiles.profile(draft) == nil)
    }

    @Test func openingAPageKeepsTheDraft() {
        let window = makeWindow()
        window.switchToNextProfile()
        let draft = window.profileID

        window.activeTab.load(URL(string: "https://example.com")!)
        window.tabDidNavigate()
        #expect(!window.profiles.isDraft(draft))

        window.switchToPreviousProfile()
        #expect(window.profiles.profile(draft) != nil)
    }

    @Test func swipesMoveBetweenExistingProfiles() {
        let window = makeWindow()
        let work = window.profiles.add(name: "Work", color: .orange)
        window.switchToNextProfile()
        #expect(window.profileID == work.id)
        window.switchToPreviousProfile()
        #expect(window.profileID == Profile.defaultID)
        window.switchToPreviousProfile()
        #expect(window.profileID == Profile.defaultID)
    }

    // MARK: - Janela privada e histórico

    @Test func privateWindowsSaveNothing() {
        let defaults = UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!
        let history = HistoryStore(inMemory: true)
        let window = makeWindow(defaults: defaults, isPrivate: true, history: history)
        let page = window.newTab(url: URL(string: "https://example.com/secret")!)
        window.toggleGrid(page.id)
        window.tabDidFinishLoading(page)
        window.saveSessionNow()

        let storage = BrowserStorage(defaults: defaults)
        #expect(storage.session(for: Profile.defaultID) == nil)
        #expect(storage.savedURLs(.grid, for: Profile.defaultID).isEmpty)
        #expect(history.entries(profile: Profile.defaultID).isEmpty)
    }

    @Test func privateWindowsCannotSwitchProfiles() {
        let window = makeWindow(isPrivate: true)
        let work = window.profiles.add(name: "Work", color: .orange)
        window.switchProfile(to: work.id)
        #expect(window.profileID == Profile.defaultID)
    }

    @Test func finishedPagesGoToTheHistory() {
        let history = HistoryStore(inMemory: true)
        let window = makeWindow(history: history)
        window.activeTab.load(URL(string: "https://example.com/page")!)
        window.tabDidFinishLoading(window.activeTab)

        #expect(history.entries(profile: Profile.defaultID).map(\.urlString) == ["https://example.com/page"])
    }

    @Test func suggestionsListOpenTabsBeforeHistory() {
        let history = HistoryStore(inMemory: true)
        history.recordVisit(
            url: URL(string: "https://swift.org/blog")!, title: "Swift Blog", profile: Profile.defaultID)
        let window = makeWindow(history: history)
        let open = window.newTab(url: URL(string: "https://swift.org/documentation")!)
        window.newTab()

        let suggestions = window.suggestions(for: "swift")
        #expect(suggestions.first?.kind == .openTab(open.id))
        #expect(suggestions.contains { $0.url.absoluteString == "https://swift.org/blog" && $0.kind == .history })
    }

    @Test func suggestionsListBookmarksBeforeHistory() {
        let history = HistoryStore(inMemory: true)
        let bookmarks = BookmarkStore(inMemory: true)
        history.recordVisit(
            url: URL(string: "https://swift.org/blog")!, title: "Swift Blog", profile: Profile.defaultID)
        bookmarks.add(
            url: URL(string: "https://swift.org/packages")!, title: "Swift Packages", profile: Profile.defaultID)
        let window = makeWindow(history: history, bookmarks: bookmarks)

        let kinds = window.suggestions(for: "swift").map(\.kind)
        #expect(kinds == [.bookmark, .history])
    }
}
