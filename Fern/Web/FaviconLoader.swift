import AppKit
import WebKit

/// Descobre e baixa o ícone de cada site. Guarda em memória por host, para que várias
/// abas do mesmo site não baixem o mesmo ícone.
@MainActor
final class FaviconLoader {
    static let shared = FaviconLoader()

    private var cache: [String: NSImage] = [:]
    private let session = URLSession(configuration: .ephemeral)

    /// Procura o `<link rel="icon">` da página. Roda no mundo de scripts do app
    /// (`.defaultClient`), isolado dos scripts da página.
    private static let findIconScript = """
        (() => {
          const link = document.querySelector('link[rel~="icon"], link[rel="apple-touch-icon"]');
          return link ? link.href : null;
        })()
        """

    func cachedFavicon(for pageURL: URL?) -> NSImage? {
        pageURL?.host().flatMap { cache[$0] }
    }

    func favicon(for pageURL: URL, in webView: WKWebView?) async -> NSImage? {
        guard let host = pageURL.host(), ["http", "https"].contains(pageURL.scheme?.lowercased()) else {
            return nil
        }
        if let cached = cache[host] { return cached }

        var candidates: [URL] = []
        if let webView, let href = await iconHref(in: webView), let url = URL(string: href) {
            candidates.append(url)
        }
        if let fallback = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL {
            candidates.append(fallback)
        }

        for url in candidates where ["http", "https"].contains(url.scheme?.lowercased()) {
            guard let (data, response) = try? await session.data(from: url),
                (response as? HTTPURLResponse)?.statusCode == 200,
                let image = NSImage(data: data), image.isValid
            else { continue }
            cache[host] = image
            return image
        }
        return nil
    }

    private func iconHref(in webView: WKWebView) async -> String? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(Self.findIconScript, in: nil, in: .defaultClient) { result in
                continuation.resume(returning: try? result.get() as? String)
            }
        }
    }
}
