import Foundation
import Testing

@testable import Fern

@MainActor
struct HistoryStoreTests {
    let profile = UUID()
    let other = UUID()

    @Test func revisitsUpdateTheSameEntry() {
        let store = HistoryStore(inMemory: true)
        let url = URL(string: "https://example.com")!
        store.recordVisit(url: url, title: "Example", profile: profile)
        store.recordVisit(url: url, title: "Example Domain", profile: profile)

        let entries = store.entries(profile: profile)
        #expect(entries.count == 1)
        #expect(entries.first?.visitCount == 2)
        #expect(entries.first?.title == "Example Domain")
    }

    @Test func onlyWebPagesAreRecorded() {
        let store = HistoryStore(inMemory: true)
        store.recordVisit(url: URL(string: "about:blank")!, title: "", profile: profile)
        store.recordVisit(url: URL(string: "data:text/html,oi")!, title: "", profile: profile)
        #expect(store.entries(profile: profile).isEmpty)
    }

    @Test func eachProfileHasItsOwnHistory() {
        let store = HistoryStore(inMemory: true)
        store.recordVisit(url: URL(string: "https://example.com")!, title: "", profile: profile)
        #expect(store.entries(profile: other).isEmpty)
    }

    @Test func searchesTitlesAndAddresses() {
        let store = HistoryStore(inMemory: true)
        store.recordVisit(url: URL(string: "https://swift.org")!, title: "Swift", profile: profile)
        store.recordVisit(url: URL(string: "https://webkit.org")!, title: "WebKit", profile: profile)

        #expect(store.entries(profile: profile, matching: "webkit").map(\.title) == ["WebKit"])
        #expect(store.entries(profile: profile, matching: "swift.org").map(\.title) == ["Swift"])
    }

    @Test func suggestionsFavorFrequentPages() {
        let store = HistoryStore(inMemory: true)
        let often = URL(string: "https://example.com/often")!
        store.recordVisit(url: often, title: "Often", profile: profile, at: .now.addingTimeInterval(-600))
        store.recordVisit(url: often, title: "Often", profile: profile, at: .now.addingTimeInterval(-500))
        store.recordVisit(url: URL(string: "https://example.com/once")!, title: "Once", profile: profile)

        #expect(store.suggestions(for: "example", profile: profile).first?.title == "Often")
    }

    @Test func clearsOnlyThePeriod() {
        let store = HistoryStore(inMemory: true)
        store.recordVisit(
            url: URL(string: "https://old.example")!, title: "Old", profile: profile, at: .now.addingTimeInterval(-7200)
        )
        store.recordVisit(url: URL(string: "https://new.example")!, title: "New", profile: profile)

        store.clear(profile: profile, since: ClearPeriod.lastHour.startDate())
        #expect(store.entries(profile: profile).map(\.title) == ["Old"])

        store.clear(profile: profile, since: nil)
        #expect(store.entries(profile: profile).isEmpty)
    }
}
