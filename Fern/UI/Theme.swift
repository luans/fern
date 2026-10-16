import AppKit
import SwiftUI

/// Cores e medidas da moldura do Fern. A moldura é cinza e fosca; a página e os
/// controles ficam em superfícies claras por cima dela. Tudo se adapta ao modo escuro.
enum Theme {
    /// Fundo da janela, atrás da barra lateral e da página.
    static let chrome = Color(light: 0xE4E8EA, dark: 0x1C1D20)
    /// Fundo das janelas privadas: escuro e arroxeado, para se distinguirem das comuns.
    static let privateChrome = Color(light: 0x24203A, dark: 0x1E1A30)
    /// Cartão que agrupa as abas na barra lateral.
    static let groupedCard = Color(light: 0xEDF0F2, dark: 0x25262A)
    /// Superfícies em destaque: página, aba ativa, botões e barra de endereço.
    static let surface = Color(light: 0xFFFFFF, dark: 0x2E3034)
    /// Superfície ao passar o mouse.
    static let surfaceHover = Color(light: 0xF6F7F8, dark: 0x36383D)
    /// Contorno fino das superfícies.
    static let hairline = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.08)

    static let windowPadding: CGFloat = 10
    /// Respiro entre o topo da janela e a primeira linha de botões.
    static let topInset: CGFloat = 12
    static let sidebarWidth: CGFloat = 240
    /// Limites ao redimensionar a barra lateral arrastando a borda.
    static let sidebarWidthRange: ClosedRange<Double> = 180...420
    static let topRowHeight: CGFloat = 30
    static let controlSize: CGFloat = 28
    static let controlRadius: CGFloat = 8
    static let pageRadius: CGFloat = 12
}

extension Color {
    /// Cor que muda com a aparência do sistema, a partir de valores hexadecimais.
    init(light: UInt32, dark: UInt32) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Botão quadrado e claro da moldura (voltar, recarregar, configurações…).
struct ChromeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .frame(width: Theme.controlSize, height: Theme.controlSize)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .fill(isHovering && isEnabled ? Theme.surfaceHover : Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
            .onHover { isHovering = $0 }
    }
}

extension ButtonStyle where Self == ChromeButtonStyle {
    static var chrome: ChromeButtonStyle { ChromeButtonStyle() }
}
