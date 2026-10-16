import Darwin
import Foundation

/// Decide se o texto digitado na barra de endereço é uma URL, um domínio ou uma busca.
///
/// Regras (spec, seção 5.4):
/// 1. Tem esquema (`https://`, `file://`, `mailto:`…)? Usa como está.
/// 2. Parece domínio (tem ponto e TLD válido) ou é `localhost`/IP? Completa o esquema.
///    Domínios ganham `https://`. `localhost`, `*.localhost` e IPs ganham `http://`,
///    porque servidores locais quase nunca têm certificado.
/// 3. Caso contrário, vira busca no buscador configurado.
struct AddressBarParser: Sendable {
    enum Result: Equatable, Sendable {
        case url(URL)
        case search(URL)

        var url: URL {
            switch self {
            case .url(let url), .search(let url): url
            }
        }
    }

    var searchEngine: SearchEngine = .default

    /// Esquemas sem `//` aceitos quando digitados (`mailto:fulano@exemplo.com`).
    /// `javascript:` fica de fora de propósito: digitado na barra, vira busca.
    private static let opaqueSchemes: Set<String> = [
        "about", "data", "mailto", "tel", "sms", "facetime", "facetime-audio",
    ]

    func parse(_ input: String) -> Result? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = Self.urlWithExplicitScheme(text) ?? Self.urlFromHostLikeText(text) {
            return .url(url)
        }
        return .search(searchEngine.searchURL(for: text))
    }

    // MARK: - Esquema explícito

    private static func urlWithExplicitScheme(_ text: String) -> URL? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let scheme = text[..<colon].lowercased()
        guard isValidScheme(scheme), scheme != "javascript" else { return nil }

        let rest = text[text.index(after: colon)...]
        if rest.hasPrefix("//") {
            guard let url = URL(string: text) else { return nil }
            // "https://" sozinho não é um endereço.
            if scheme == "http" || scheme == "https" {
                guard let host = url.host(), !host.isEmpty else { return nil }
            }
            return url
        }
        if opaqueSchemes.contains(scheme), !rest.isEmpty, !text.contains(where: \.isWhitespace) {
            return URL(string: text)
        }
        return nil
    }

    private static func isValidScheme(_ scheme: String) -> Bool {
        guard let first = scheme.unicodeScalars.first, first.isASCIILetter else { return false }
        return scheme.unicodeScalars.allSatisfy {
            $0.isASCIILetter || $0.isASCIIDigit || "+-.".unicodeScalars.contains($0)
        }
    }

    // MARK: - Domínio, localhost e IP

    private static func urlFromHostLikeText(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else { return nil }

        let authorityEnd = text.firstIndex(where: { "/?#".contains($0) }) ?? text.endIndex
        guard let host = host(fromAuthority: String(text[..<authorityEnd])) else { return nil }

        let scheme: String
        if isLocalHost(host) || isIPAddress(host) {
            scheme = "http"
        } else if looksLikeDomain(host) {
            scheme = "https"
        } else {
            return nil
        }
        return URL(string: "\(scheme)://\(text)")
    }

    /// Separa o host da porta. Retorna `nil` se a porta for inválida.
    private static func host(fromAuthority authority: String) -> String? {
        let host: Substring
        let port: Substring?

        if authority.hasPrefix("[") {
            // IPv6 entre colchetes: [::1]:8080
            guard let close = authority.firstIndex(of: "]") else { return nil }
            host = authority[authority.index(after: authority.startIndex)..<close]
            let rest = authority[authority.index(after: close)...]
            guard rest.isEmpty || rest.hasPrefix(":") else { return nil }
            port = rest.isEmpty ? nil : rest.dropFirst()
            guard isIPv6Address(String(host)) else { return nil }
        } else {
            let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 2 else { return nil }
            host = parts[0]
            port = parts.count == 2 ? parts[1] : nil
        }

        if let port {
            guard !port.isEmpty, port.count <= 5, port.allSatisfy(\.isASCIIDigit),
                let value = Int(port), value <= 65_535
            else { return nil }
        }
        return host.isEmpty ? nil : host.lowercased()
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".localhost")
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var ipv4 = in_addr()
        return inet_pton(AF_INET, host, &ipv4) == 1 || isIPv6Address(host)
    }

    private static func isIPv6Address(_ host: String) -> Bool {
        var ipv6 = in6_addr()
        return inet_pton(AF_INET6, host, &ipv6) == 1
    }

    /// Pelo menos dois rótulos, cada um com letras, números ou hífen, e um TLD
    /// alfabético com duas letras ou mais (aceita domínios internacionais e `xn--`).
    private static func looksLikeDomain(_ host: String) -> Bool {
        let trimmed = host.hasSuffix(".") ? String(host.dropLast()) : host
        let labels = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        for label in labels {
            guard !label.isEmpty, label.count <= 63, !label.hasPrefix("-"), !label.hasSuffix("-"),
                label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            else { return false }
        }

        guard let tld = labels.last else { return false }
        return tld.hasPrefix("xn--") || (tld.count >= 2 && tld.allSatisfy(\.isLetter))
    }
}

extension Unicode.Scalar {
    fileprivate var isASCIILetter: Bool { ("a"..."z").contains(self) || ("A"..."Z").contains(self) }
    fileprivate var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
