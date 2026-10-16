import SwiftUI

/// Uma janela do navegador. O estado (`BrowserWindow`) é criado uma vez só, quando a
/// janela aparece, e não a cada vez que o SwiftUI recria esta view.
struct ContentView: View {
    var isPrivate = false

    @State private var window: BrowserWindow?

    var body: some View {
        Group {
            if let window {
                BrowserWindowView(window: window)
            } else {
                Theme.chrome
            }
        }
        .onAppear {
            if window == nil { window = BrowserWindow(isPrivate: isPrivate) }
        }
    }
}

/// Moldura cinza com a barra lateral à esquerda e, à direita, a faixa de navegação e a
/// página flutuando num cartão. Janelas privadas usam uma moldura escura própria.
private struct BrowserWindowView: View {
    @Bindable var window: BrowserWindow
    @State private var hostWindow = HostWindow()
    /// Largura da barra lateral, ajustada arrastando a borda dela. Vale para todas as janelas.
    @AppStorage("sidebarWidth") private var sidebarWidth = Double(Theme.sidebarWidth)

    var body: some View {
        let tab = window.activeTab

        HStack(spacing: 0) {
            if window.isSidebarVisible {
                TabSidebar(window: window, width: sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                // A borda entre a barra lateral e a página: arraste para mudar a largura;
                // arrastar bem para a esquerda esconde a barra.
                ResizeHandle(
                    axis: .horizontal, value: $sidebarWidth, range: Theme.sidebarWidthRange,
                    defaultValue: Double(Theme.sidebarWidth), thickness: Theme.windowPadding
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { window.isSidebarVisible = false }
                }
            }
            VStack(spacing: Theme.windowPadding) {
                TopBar(window: window, tab: tab)
                    .padding(.top, Theme.topInset)
                    // As sugestões da barra de endereço aparecem por cima da página.
                    .zIndex(1)
                PageCard(window: window, tab: tab)
            }
        }
        .padding([.horizontal, .bottom], Theme.windowPadding)
        .background(window.isPrivate ? Theme.privateChrome : Theme.chrome)
        .ignoresSafeArea(.container, edges: .top)
        .background { WindowConfigurator(hostWindow: hostWindow) }
        .environment(\.hostWindow, hostWindow)
        // A janela privada é sempre escura, para não ser confundida com uma comum.
        .preferredColorScheme(window.isPrivate ? .dark : nil)
        .navigationTitle(tab.displayTitle)
        .focusedSceneValue(window)
        .background { ZoomShortcutAliases(tab: tab) }
        .background { DevToolsShortcut(window: window) }
        .sheet(isPresented: $window.isHistoryVisible) {
            HistoryView(window: window)
        }
        .sheet(isPresented: $window.isBookmarksVisible) {
            BookmarksView(window: window)
        }
        .frame(minWidth: 720, minHeight: 400)
    }
}

/// A página, num cartão com cantos arredondados por cima da moldura.
private struct PageCard: View {
    let window: BrowserWindow
    let tab: Tab

    /// Altura do inspetor, ajustada arrastando a borda de cima dele.
    @AppStorage("devToolsHeight") private var devToolsHeight = 280.0

    var body: some View {
        VStack(spacing: 0) {
            if window.isFindBarVisible {
                FindBar(window: window)
                Divider()
            }
            ZStack(alignment: .top) {
                WebView(
                    tab: tab, cornerRadius: Theme.pageRadius, roundsTopCorners: !window.isFindBarVisible,
                    roundsBottomCorners: !window.isDevToolsVisible)
                if let error = tab.loadError {
                    LoadErrorView(error: error) { tab.reload() }
                } else if tab.isBlank {
                    StartPage()
                }
                LoadingProgressBar(progress: tab.estimatedProgress, isLoading: tab.isLoading)
                if let request = tab.pendingPermission {
                    PermissionBanner(tab: tab, request: request)
                        .id(request.id)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            if window.isDevToolsVisible {
                Divider()
                    .overlay(alignment: .center) {
                        // Arraste a borda para cima para aumentar o inspetor.
                        ResizeHandle(
                            axis: .vertical, value: $devToolsHeight, range: 120...700, defaultValue: 280,
                            grows: false, thickness: 8)
                    }
                DevToolsPanel(window: window, tab: tab)
                    .frame(height: devToolsHeight)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.pageRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.pageRadius).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }
}

/// O menu mostra ⌘+, mas em teclados US e ABNT o "+" exige Shift. Este botão invisível
/// faz ⌘= funcionar também, como no Safari.
private struct ZoomShortcutAliases: View {
    let tab: Tab

    var body: some View {
        Button("Zoom In") { tab.zoomIn() }
            .keyboardShortcut("=", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

/// Exibida enquanto a aba não tem página.
private struct StartPage: View {
    var body: some View {
        VStack(spacing: 8) {
            Text(verbatim: "Fern")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
            Text("Type an address or search the web.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }
}

private struct LoadErrorView: View {
    let error: Tab.LoadError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Can't Open This Page")
                .font(.title2.weight(.semibold))
            Text(verbatim: error.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            if let url = error.url {
                Text(verbatim: url.absoluteString)
                    .font(.callout.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Try Again", action: retry)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .frame(maxWidth: 460)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }
}

/// F12 abre e fecha o inspetor. Nos MacBooks, o F12 costuma ser a tecla de volume: aí é
/// preciso segurar fn, ou usar ⌥⌘I (menu Desenvolvedor).
private struct DevToolsShortcut: View {
    let window: BrowserWindow

    var body: some View {
        Button("Developer Tools") { window.isDevToolsVisible.toggle() }
            .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF12FunctionKey)!)), modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
