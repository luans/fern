import Foundation
import Observation
import WebKit

/// Estado do inspetor de uma aba: console, árvore do HTML, código-fonte e recursos.
/// Os dados vêm do `DevToolsScript`, que roda na página.
@MainActor
@Observable
final class DevToolsSession {
    struct ConsoleEntry: Identifiable, Equatable {
        enum Kind: String {
            case log, info, warn, error, debug
            /// O que você digitou no console.
            case input
            /// A resposta do que você digitou.
            case result
        }

        let id = UUID()
        let kind: Kind
        let message: String
    }

    struct DOMNode: Identifiable {
        let id: Int
        let label: String
        let isText: Bool
        let children: [DOMNode]?
    }

    struct NetworkEntry: Identifiable {
        let id: Int
        let url: String
        let type: String
        let size: Int
        let duration: Double

        var name: String {
            let url = URL(string: url)
            let last = url?.lastPathComponent ?? ""
            return last.isEmpty || last == "/" ? (url?.host() ?? self.url) : last
        }
    }

    private static let consoleLimit = 1000

    private(set) var console: [ConsoleEntry] = []
    private(set) var dom: DOMNode?
    private(set) var html: String?
    private(set) var network: [NetworkEntry] = []

    // MARK: - Console

    /// Busca as mensagens novas da página.
    func pollConsole(in webView: WKWebView) async {
        guard let json = await Self.evaluateString("\(DevToolsScript.bridge)?.drain() ?? '[]'", in: webView),
            let entries = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]],
            !entries.isEmpty
        else { return }
        for entry in entries {
            let kind = ConsoleEntry.Kind(rawValue: entry["level"] as? String ?? "") ?? .log
            append(ConsoleEntry(kind: kind, message: entry["message"] as? String ?? ""))
        }
    }

    /// Roda o código no mundo da página, como o console de um navegador.
    func evaluate(_ code: String, in webView: WKWebView) async {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        append(ConsoleEntry(kind: .input, message: code))
        let (message, failed) = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(code, in: nil, in: .page) { result in
                continuation.resume(returning: Self.describe(result))
            }
        }
        append(ConsoleEntry(kind: failed ? .error : .result, message: message))
        await pollConsole(in: webView)
    }

    func clearConsole() {
        console.removeAll()
    }

    // MARK: - Elementos e rede

    func loadDOM(from webView: WKWebView) async {
        guard let json = await Self.evaluateString("\(DevToolsScript.bridge)?.dom() ?? 'null'", in: webView),
            let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else {
            dom = nil
            return
        }
        var nextID = 0
        dom = Self.node(from: root, nextID: &nextID)
    }

    func loadHTML(from webView: WKWebView) async {
        let source = await Self.evaluateString("document.documentElement.outerHTML", in: webView)
        // Páginas enormes deixariam a lista lenta; o começo basta para ler.
        html = source.map { $0.count > 300_000 ? String($0.prefix(300_000)) + "\n…" : $0 }
    }

    func loadNetwork(from webView: WKWebView) async {
        guard let json = await Self.evaluateString("\(DevToolsScript.bridge)?.network() ?? '[]'", in: webView),
            let entries = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        else { return }
        network = entries.enumerated().map { index, entry in
            NetworkEntry(
                id: index,
                url: entry["url"] as? String ?? "",
                type: entry["type"] as? String ?? "",
                size: entry["size"] as? Int ?? 0,
                duration: entry["duration"] as? Double ?? 0)
        }
    }

    /// Outra página carregou: o que era da anterior não vale mais.
    func pageDidChange() {
        console.removeAll()
        dom = nil
        html = nil
        network = []
    }

    // MARK: - Interno

    private func append(_ entry: ConsoleEntry) {
        console.append(entry)
        if console.count > Self.consoleLimit { console.removeFirst(console.count - Self.consoleLimit) }
    }

    private static func evaluateString(_ script: String, in webView: WKWebView) async -> String? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: .page) { result in
                continuation.resume(returning: try? result.get() as? String)
            }
        }
    }

    /// Transforma a resposta do WebKit no texto do console. `true` em `failed` para erros.
    static func describe(_ result: Result<Any, any Error>) -> (message: String, failed: Bool) {
        switch result {
        case .success(let value):
            return (describe(value), false)
        case .failure(let error as NSError):
            if error.domain == WKError.errorDomain, error.code == WKError.javaScriptResultTypeIsUnsupported.rawValue {
                // `undefined`, funções e elementos não atravessam para o app.
                return ("undefined", false)
            }
            let message = error.userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            return (message, true)
        }
    }

    static func describe(_ value: Any) -> String {
        switch value {
        case is NSNull:
            return "null"
        case let string as String:
            return "\"\(string)\""
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case let date as Date:
            return date.ISO8601Format()
        default:
            if JSONSerialization.isValidJSONObject(value),
                let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
                let json = String(data: data, encoding: .utf8)
            {
                return json
            }
            return String(describing: value)
        }
    }

    private static func node(from object: [String: Any], nextID: inout Int) -> DOMNode {
        let id = nextID
        nextID += 1
        if let text = object["text"] as? String {
            return DOMNode(id: id, label: "\"\(text)\"", isText: true, children: nil)
        }
        var label = "<" + (object["tag"] as? String ?? "?")
        if let elementID = object["id"] as? String { label += " id=\"\(elementID)\"" }
        if let classes = object["classes"] as? String {
            label += " class=\"\(classes.replacingOccurrences(of: ".", with: " "))\""
        }
        label += ">"
        let children = (object["children"] as? [[String: Any]])?.map { node(from: $0, nextID: &nextID) }
        return DOMNode(id: id, label: label, isText: false, children: children?.isEmpty == false ? children : nil)
    }
}
