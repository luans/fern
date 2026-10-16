import AppKit
import SwiftUI

/// Faixa acima da página: navegação, barra de endereço e, à direita, perfil,
/// configurações e downloads. As áreas vazias arrastam a janela.
struct TopBar: View {
    let window: BrowserWindow
    let tab: Tab

    var body: some View {
        HStack(spacing: 6) {
            if !window.isSidebarVisible {
                // Com a barra lateral escondida, os botões da janela ficam aqui.
                WindowControls()
                    .padding(.trailing, 6)
                SidebarToggleButton(window: window)
            }

            Button {
                tab.goBack()
            } label: {
                Label("Back", systemImage: "chevron.backward")
            }
            .help("Back")
            .disabled(!tab.canGoBack)

            Button {
                tab.goForward()
            } label: {
                Label("Forward", systemImage: "chevron.forward")
            }
            .help("Forward")
            .disabled(!tab.canGoForward)

            Button {
                if tab.isLoading { tab.stopLoading() } else { tab.reload() }
            } label: {
                if tab.isLoading {
                    Label("Stop", systemImage: "xmark")
                } else {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
            .help(tab.isLoading ? "Stop" : "Reload")
            .disabled(tab.isBlank)

            Spacer(minLength: 12)

            AddressBar(window: window, tab: tab)
                .frame(minWidth: 220, idealWidth: 620, maxWidth: 680)

            Spacer(minLength: 12)

            if !window.isPrivate {
                ProfileMenuButton(window: window)
            }
            SettingsLink {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .help("Settings")
            DownloadsButton(window: window)
        }
        .buttonStyle(.chrome)
        .frame(height: Theme.topRowHeight)
        .background { WindowDragArea() }
    }
}
