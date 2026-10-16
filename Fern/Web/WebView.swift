import SwiftUI
import WebKit

/// Exibe o `WKWebView` da aba ativa. O contêiner troca de web view quando a aba muda,
/// sem recriar as páginas (cada aba mantém a sua).
struct WebView: NSViewRepresentable {
    let tab: Tab
    var cornerRadius: CGFloat = 0
    /// `false` quando há algo acima da página no mesmo cartão (ex.: barra de busca).
    var roundsTopCorners = true
    /// `false` quando há algo abaixo da página no mesmo cartão (ex.: inspetor).
    var roundsBottomCorners = true

    func makeNSView(context: Context) -> WebViewContainer {
        let container = WebViewContainer()
        updateNSView(container, context: context)
        return container
    }

    func updateNSView(_ container: WebViewContainer, context: Context) {
        container.show(tab.webView)
        container.setCornerRadius(cornerRadius, top: roundsTopCorners, bottom: roundsBottomCorners)
    }
}

final class WebViewContainer: NSView {
    /// O SwiftUI não recorta views do AppKit, então os cantos são arredondados na camada.
    func setCornerRadius(_ radius: CGFloat, top: Bool, bottom: Bool) {
        wantsLayer = true
        guard let layer else { return }
        // Na camada de uma NSView, "max Y" é a borda de cima.
        var corners: CACornerMask = []
        if top { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        if bottom { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        layer.cornerRadius = corners.isEmpty ? 0 : radius
        layer.maskedCorners = corners
        layer.masksToBounds = radius > 0
    }

    func show(_ webView: WKWebView) {
        guard webView.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
