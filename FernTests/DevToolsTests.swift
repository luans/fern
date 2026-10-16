import Foundation
import Testing
import WebKit

@testable import Fern

@MainActor
struct DevToolsTests {
    @Test func describesSimpleValues() {
        #expect(DevToolsSession.describe(NSNull()) == "null")
        #expect(DevToolsSession.describe("oi") == "\"oi\"")
        #expect(DevToolsSession.describe(NSNumber(value: 42)) == "42")
        #expect(DevToolsSession.describe(NSNumber(value: true)) == "true")
    }

    @Test func describesObjectsAsJSON() {
        let text = DevToolsSession.describe(["b": 2, "a": 1] as [String: Any])
        #expect(text.contains("\"a\" : 1"))
        #expect(text.firstRange(of: "\"a\"")!.lowerBound < text.firstRange(of: "\"b\"")!.lowerBound)
    }

    @Test func undefinedIsNotAnError() {
        let error = NSError(domain: WKError.errorDomain, code: WKError.javaScriptResultTypeIsUnsupported.rawValue)
        let (message, failed) = DevToolsSession.describe(.failure(error))
        #expect(message == "undefined")
        #expect(!failed)
    }

    @Test func exceptionsShowTheirMessage() {
        let error = NSError(
            domain: WKError.errorDomain, code: WKError.javaScriptExceptionOccurred.rawValue,
            userInfo: ["WKJavaScriptExceptionMessage": "ReferenceError: x is not defined"])
        let (message, failed) = DevToolsSession.describe(.failure(error))
        #expect(message == "ReferenceError: x is not defined")
        #expect(failed)
    }

    @Test func eachTabHasItsOwnSessionAndItIsResetOnNavigation() {
        let window = BrowserWindow(
            profiles: ProfileStore(defaults: UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!),
            history: HistoryStore(inMemory: true),
            bookmarks: BookmarkStore(inMemory: true),
            storage: BrowserStorage(defaults: UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!),
            restoresSession: false,
            restoreTracker: SessionRestoreTracker()
        )
        let first = window.activeTab
        let second = window.newTab()
        #expect(window.devTools(for: first) === window.devTools(for: first))
        #expect(window.devTools(for: first) !== window.devTools(for: second))
    }
}
