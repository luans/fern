import SwiftUI

@main
struct FernApp: App {
    static let privateWindowID = "private"

    init() {
        // Ignora as janelas salvas pela restauração do macOS. Ela não traz as páginas de
        // volta (o estado das abas é nosso) e, se o app foi fechado sem janelas, reabria
        // sem nenhuma. Restaurar a sessão anterior fica para uma opção própria do Fern.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
        // Carrega (ou compila, na primeira vez) as regras do bloqueador de conteúdo.
        Task { await ContentBlocker.shared.prepare() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)
        // Sem barra de título: a moldura do Fern desenha tudo, e os botões da janela
        // ficam sobre a barra lateral. O título continua valendo (menu Janela, Mission
        // Control) e segue o da página.
        .windowStyle(.hiddenTitleBar)
        .commands {
            BrowserCommands()
        }

        // Janela privada (⌘⇧N): sem histórico, sem sessão salva e com cookies e dados de
        // sites só na memória.
        WindowGroup("Private Browsing", id: FernApp.privateWindowID) {
            ContentView(isPrivate: true)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
        }
    }
}
