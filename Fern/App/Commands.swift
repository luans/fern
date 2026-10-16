import SwiftUI

/// Itens de menu e atalhos globais. Agem sobre a janela em foco.
struct BrowserCommands: Commands {
    @FocusedValue(BrowserWindow.self) private var window
    @Environment(\.openWindow) private var openWindow

    private var tab: Tab? { window?.activeTab }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") { window?.newTab() }
                .keyboardShortcut("t")
                .disabled(window == nil)
            Button("New Private Window") { openWindow(id: FernApp.privateWindowID) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open Location…") { window?.focusAddressBar() }
                .keyboardShortcut("l")
                .disabled(window == nil)
            Divider()
            // Fica antes do "Fechar" do sistema no menu Arquivo, então o ⌘W chega aqui
            // primeiro. Sem janela do navegador em foco (ex.: Ajustes), fecha a janela.
            Button("Close Tab") { closeActiveTab() }
                .keyboardShortcut("w")
            Button(tab?.isPinned ?? false ? "Unpin Tab" : "Pin Tab") {
                guard let window else { return }
                window.togglePin(window.activeTabID)
            }
            .disabled(tab == nil || (tab?.isBlank ?? true))
            Button(tab?.isInGrid ?? false ? "Remove from Grid" : "Add to Grid") {
                guard let window else { return }
                window.toggleGrid(window.activeTabID)
            }
            .disabled(tab == nil || (tab?.isBlank ?? true))
            Button("Reopen Closed Tab") { window?.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!(window?.canReopenClosedTab ?? false))
        }

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { window?.showFindBar() }
                .keyboardShortcut("f")
                .disabled(window == nil)
            Button("Find Next") { find { await $0.findNext() } }
                .keyboardShortcut("g")
                .disabled(window?.findQuery.isEmpty ?? true)
            Button("Find Previous") { find { await $0.findPrevious() } }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(window?.findQuery.isEmpty ?? true)
        }

        CommandGroup(before: .toolbar) {
            Button(window?.isSidebarVisible ?? true ? "Hide Sidebar" : "Show Sidebar") {
                guard let window else { return }
                withAnimation(.easeInOut(duration: 0.2)) { window.isSidebarVisible.toggle() }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(window == nil)
            Divider()
            Button("Reload") { tab?.reload() }
                .keyboardShortcut("r")
                .disabled(tab == nil)
            Button("Stop") { tab?.stopLoading() }
                .keyboardShortcut(".")
                .disabled(!(tab?.isLoading ?? false))
            Divider()
            // ⌘= também aumenta o zoom (ver ZoomShortcutAliases em ContentView).
            Button("Zoom In") { tab?.zoomIn() }
                .keyboardShortcut("+")
                .disabled(!(tab?.canZoomIn ?? false))
            Button("Zoom Out") { tab?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(!(tab?.canZoomOut ?? false))
            Button("Actual Size") { tab?.resetZoom() }
                .keyboardShortcut("0")
                .disabled(tab == nil)
            Divider()
        }

        CommandGroup(before: .windowList) {
            Button(tab?.isAudioMuted ?? false ? "Unmute Tab" : "Mute Tab") { tab?.toggleAudioMuted() }
                .disabled(tab == nil)
            Divider()
            Button("Show Next Tab") { window?.selectNextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled((window?.tabs.count ?? 0) < 2)
            Button("Show Previous Tab") { window?.selectPreviousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled((window?.tabs.count ?? 0) < 2)
            Menu("Go to Tab") {
                ForEach(1..<9) { number in
                    Button("Tab \(number)") { window?.selectTab(number: number) }
                        .keyboardShortcut(KeyEquivalent(Character(String(number))))
                        .disabled((window?.tabs.count ?? 0) < number)
                }
                Button("Last Tab") { window?.selectTab(number: 9) }
                    .keyboardShortcut("9")
            }
            .disabled(window == nil)
            Divider()
        }

        CommandMenu("Bookmarks") {
            Button("Add to Bookmarks") { window?.bookmarkActiveTab() }
                .keyboardShortcut("d")
                .disabled(!["http", "https"].contains(tab?.url?.scheme?.lowercased()))
            Button("Show Bookmarks") { window?.isBookmarksVisible = true }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(window == nil)
            if let window {
                let bookmarks = window.bookmarks.bookmarks(profile: window.profileID).prefix(20)
                if !bookmarks.isEmpty {
                    Divider()
                    ForEach(Array(bookmarks), id: \.persistentModelID) { bookmark in
                        Button(bookmark.displayTitle) { window.open(bookmark) }
                    }
                }
            }
        }

        CommandMenu("Develop") {
            // F12 também abre e fecha (ver ZoomShortcutAliases em ContentView).
            Button(window?.isDevToolsVisible ?? false ? "Hide Developer Tools" : "Show Developer Tools") {
                window?.isDevToolsVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(window == nil)
        }

        CommandMenu("History") {
            Button("Show All History") { window?.isHistoryVisible = true }
                .keyboardShortcut("y")
                .disabled(window == nil)
            Button("Show Downloads") { window?.showDownloads() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(window == nil)
            Divider()
            Button("Back") { tab?.goBack() }
                .keyboardShortcut("[")
                .disabled(!(tab?.canGoBack ?? false))
            Button("Forward") { tab?.goForward() }
                .keyboardShortcut("]")
                .disabled(!(tab?.canGoForward ?? false))
        }
    }

    private func closeActiveTab() {
        guard let window else {
            NSApp.keyWindow?.performClose(nil)
            return
        }
        if !window.closeTab(window.activeTabID) {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    private func find(_ action: @escaping @MainActor (BrowserWindow) async -> Void) {
        guard let window else { return }
        Task { await action(window) }
    }
}
