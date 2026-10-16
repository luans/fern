import Foundation
import Testing

@testable import Fern

@MainActor
struct ContentBlockerTests {
    private func makeBlocker() -> ContentBlocker {
        ContentBlocker(defaults: UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!)
    }

    @Test func ignoresWWW() {
        #expect(ContentBlocker.normalizedHost("WWW.Example.com") == "example.com")
        #expect(ContentBlocker.normalizedHost("") == nil)
    }

    @Test func exceptionsArePerSite() {
        let blocker = makeBlocker()
        let site = URL(string: "https://www.example.com/page")!
        let other = URL(string: "https://example.org")!

        blocker.setBlocking(false, on: site)
        #expect(blocker.allowedHosts == ["example.com"])
        #expect(!blocker.isBlocking(on: URL(string: "https://example.com/other")!) || !blocker.isEnabled)
        #expect(blocker.isBlocking(on: other) == blocker.isEnabled)

        blocker.setBlocking(true, on: site)
        #expect(blocker.allowedHosts.isEmpty)
    }

    @Test func neverBlocksNonWebPages() {
        #expect(!makeBlocker().isBlocking(on: URL(string: "about:blank")!))
    }

    @Test func bundledListIsValidJSON() throws {
        let url = try #require(Bundle.main.url(forResource: "blocklist", withExtension: "json"))
        let rules = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]]
        #expect((rules?.count ?? 0) > 50)
    }
}

struct DownloadDestinationTests {
    let folder = URL(fileURLWithPath: "/Downloads")

    @Test func keepsTheSuggestedName() {
        let url = DownloadManager.uniqueDestination(for: "report.pdf", in: folder) { _ in false }
        #expect(url.lastPathComponent == "report.pdf")
    }

    @Test func numbersRepeatedNames() {
        let existing: Set<String> = ["report.pdf", "report 2.pdf"]
        let url = DownloadManager.uniqueDestination(for: "report.pdf", in: folder) {
            existing.contains($0.lastPathComponent)
        }
        #expect(url.lastPathComponent == "report 3.pdf")
    }

    @Test func removesPathSeparators() {
        let url = DownloadManager.uniqueDestination(for: "../a/b.txt", in: folder) { _ in false }
        #expect(url.deletingLastPathComponent() == folder)
    }

    @Test func namesFilesWithoutAName() {
        let url = DownloadManager.uniqueDestination(for: "", in: folder) { _ in false }
        #expect(url.lastPathComponent == "download")
    }
}

struct ClearPeriodTests {
    @Test func periodsStartAtTheRightTime() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ClearPeriod.lastHour.startDate(now: now, calendar: calendar) == now.addingTimeInterval(-3600))
        #expect(ClearPeriod.today.startDate(now: now, calendar: calendar) == calendar.startOfDay(for: now))
        #expect(ClearPeriod.allTime.startDate(now: now, calendar: calendar) == nil)
    }
}
