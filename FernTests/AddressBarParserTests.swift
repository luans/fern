import Foundation
import Testing

@testable import Fern

struct AddressBarParserTests {
    let parser = AddressBarParser(searchEngine: .duckDuckGo)

    private func url(_ input: String) -> String? {
        guard case .url(let url) = parser.parse(input) else { return nil }
        return url.absoluteString
    }

    private func search(_ input: String) -> String? {
        guard case .search(let url) = parser.parse(input) else { return nil }
        return url.absoluteString
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func emptyInputIsIgnored(_ input: String) {
        #expect(parser.parse(input) == nil)
    }

    @Test(arguments: [
        "https://apple.com",
        "http://example.com/a?b=c#d",
        "file:///Users/Shared/index.html",
        "ftp://ftp.example.com/file.txt",
        "mailto:fulano@example.com",
        "tel:+5511999999999",
        "about:blank",
    ])
    func explicitSchemeIsKept(_ input: String) {
        #expect(url(input) == input)
    }

    @Test(arguments: [
        ("apple.com", "https://apple.com"),
        ("www.apple.com/mac", "https://www.apple.com/mac"),
        ("example.com:8443/path?q=1", "https://example.com:8443/path?q=1"),
        ("sub.domain.co.uk", "https://sub.domain.co.uk"),
        ("example.com.", "https://example.com."),
        ("  apple.com  ", "https://apple.com"),
    ])
    func domainGetsHTTPS(_ input: String, _ expected: String) {
        #expect(url(input) == expected)
    }

    @Test(arguments: [
        ("localhost", "http://localhost"),
        ("localhost:3000", "http://localhost:3000"),
        ("app.localhost:5173/login", "http://app.localhost:5173/login"),
        ("127.0.0.1:8080/x", "http://127.0.0.1:8080/x"),
        ("192.168.0.1", "http://192.168.0.1"),
        ("[::1]:8080", "http://[::1]:8080"),
    ])
    func localAddressesGetHTTP(_ input: String, _ expected: String) {
        #expect(url(input) == expected)
    }

    @Test func internationalDomainIsAURL() throws {
        let result = try #require(parser.parse("café.com.br"))
        guard case .url(let url) = result else {
            Issue.record("Esperava URL, veio \(result)")
            return
        }
        #expect(url.scheme == "https")
    }

    @Test(arguments: [
        ("swift concurrency", "https://duckduckgo.com/?q=swift%20concurrency"),
        ("c++", "https://duckduckgo.com/?q=c%2B%2B"),
        ("a&b=c", "https://duckduckgo.com/?q=a%26b%3Dc"),
        ("o que é webkit?", "https://duckduckgo.com/?q=o%20que%20%C3%A9%20webkit%3F"),
        ("javascript:alert(1)", "https://duckduckgo.com/?q=javascript:alert(1)"),
        ("fulano@example.com", "https://duckduckgo.com/?q=fulano@example.com"),
        ("1.5", "https://duckduckgo.com/?q=1.5"),
        ("macos", "https://duckduckgo.com/?q=macos"),
        ("example.com:99999", "https://duckduckgo.com/?q=example.com:99999"),
        ("https://", "https://duckduckgo.com/?q=https:%2F%2F"),
        ("-bad-.com", "https://duckduckgo.com/?q=-bad-.com"),
        ("example.com/a b", "https://duckduckgo.com/?q=example.com%2Fa%20b"),
    ])
    func everythingElseIsASearch(_ input: String, _ expected: String) {
        #expect(search(input) == expected)
    }

    @Test(arguments: [
        (SearchEngine.google, "https://www.google.com/search?q=swift"),
        (SearchEngine.bing, "https://www.bing.com/search?q=swift"),
        (SearchEngine.brave, "https://search.brave.com/search?q=swift"),
        (SearchEngine.ecosia, "https://www.ecosia.org/search?q=swift"),
    ])
    func usesConfiguredSearchEngine(_ engine: SearchEngine, _ expected: String) {
        let parser = AddressBarParser(searchEngine: engine)
        #expect(parser.parse("swift") == .search(URL(string: expected)!))
    }
}
