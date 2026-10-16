import AppKit
import SwiftUI

/// Barra lateral: botões da janela, abas na grade de ícones, cartão de abas (as
/// fixadas no topo) e o seletor de perfis. Arraste uma aba sobre outra para reordenar;
/// ela passa para a seção da aba sobre a qual foi solta. Um gesto horizontal com dois
/// dedos troca de perfil.
struct TabSidebar: View {
    let window: BrowserWindow
    var width: CGFloat = Theme.sidebarWidth

    /// Aba sob o cursor durante um arraste, para mostrar onde a aba vai cair.
    @State private var dropTargetID: Tab.ID?
    @AppStorage(Experiment.systemMonitor.storageKey)
    private var showsSystemMonitor = Experiment.systemMonitor.isEnabledByDefault

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.windowPadding) {
            header

            ScrollView {
                tabsOfProfile
                    .id(window.profileID)
                    .transition(
                        .push(from: window.lastProfileSwitchWasForward ? .trailing : .leading))
            }
            .scrollIndicators(.never)
            .clipped()

            if window.profiles.isDraft(window.profileID) {
                Text("New profile. Open a page to keep it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            if showsSystemMonitor {
                SystemMonitorIndicator()
            }
            if window.isPrivate {
                PrivateBrowsingBadge()
            } else {
                ProfileSwitcher(window: window)
            }
        }
        .frame(width: width)
        .background {
            HorizontalSwipeDetector { direction in
                withAnimation(.easeInOut(duration: 0.25)) {
                    switch direction {
                    case .next: window.switchToNextProfile()
                    case .previous: window.switchToPreviousProfile()
                    }
                }
            }
        }
    }

    private var tabsOfProfile: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !window.gridTabs.isEmpty {
                tabGrid
            }
            VStack(alignment: .leading, spacing: 6) {
                if !window.pinnedTabs.isEmpty || !window.regularTabs.isEmpty {
                    tabsCard
                }
                newTabButton
                Button {
                    window.isBookmarksVisible = true
                } label: {
                    Label("Bookmarks", systemImage: "star")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Os botões da janela ficam à esquerda; nova aba e recolher, à direita.
    private var header: some View {
        HStack(spacing: 6) {
            WindowControls()
            Spacer()
            Button {
                window.newTab()
            } label: {
                Label("New Tab", systemImage: "plus")
            }
            .buttonStyle(.chrome)
            .help("New Tab")

            SidebarToggleButton(window: window)
        }
        .frame(height: Theme.topRowHeight)
        .padding(.top, Theme.topInset)
        .background { WindowDragArea() }
    }

    private var tabGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(window.gridTabs) { tab in
                GridTile(
                    tab: tab,
                    isActive: tab.id == window.activeTabID,
                    isDropTarget: dropTargetID == tab.id,
                    select: { window.select(tab.id) }
                )
                .tabDragAndDrop(tab, in: window, dropTargetID: $dropTargetID)
                .contextMenu { contextMenu(for: tab) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Grid")
        .accessibilityIdentifier("gridTabs")
    }

    /// Fixadas no topo, uma linha, e as demais abas.
    private var tabsCard: some View {
        VStack(spacing: 2) {
            ForEach(window.pinnedTabs) { tab in
                row(for: tab)
            }
            if !window.pinnedTabs.isEmpty && !window.regularTabs.isEmpty {
                Divider()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            ForEach(window.regularTabs) { tab in
                row(for: tab)
            }
        }
        .padding(4)
        .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tabList")
    }

    private func row(for tab: Tab) -> some View {
        TabRow(
            tab: tab,
            isActive: tab.id == window.activeTabID,
            isDropTarget: dropTargetID == tab.id,
            select: { window.select(tab.id) },
            close: { close(tab) }
        )
        .tabDragAndDrop(tab, in: window, dropTargetID: $dropTargetID)
        .contextMenu { contextMenu(for: tab) }
    }

    private var newTabButton: some View {
        Button {
            window.newTab()
        } label: {
            Label("New Tab", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("newTabButton")
    }

    @ViewBuilder
    private func contextMenu(for tab: Tab) -> some View {
        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { window.togglePin(tab.id) }
            .disabled(tab.isBlank)
        Button(tab.isInGrid ? "Remove from Grid" : "Add to Grid") { window.toggleGrid(tab.id) }
            .disabled(tab.isBlank)
        Button(tab.isAudioMuted ? "Unmute Tab" : "Mute Tab") { tab.toggleAudioMuted() }
        Divider()
        Button("Close Tab") { close(tab) }
        Button("Close Other Tabs") { window.closeOtherTabs(than: tab.id) }
            .disabled(window.tabs.count < 2)
        Divider()
        Button("Reload") { tab.reload() }
            .disabled(tab.isBlank)
    }

    private func close(_ tab: Tab) {
        if !window.closeTab(tab.id) {
            // Era a última aba: fecha a janela, como no Safari.
            NSApp.keyWindow?.performClose(nil)
        }
    }
}

extension View {
    /// Torna a aba arrastável e um alvo para soltar outras abas.
    fileprivate func tabDragAndDrop(
        _ tab: Tab,
        in window: BrowserWindow,
        dropTargetID: Binding<Tab.ID?>
    ) -> some View {
        draggable(tab.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                dropTargetID.wrappedValue = nil
                guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                withAnimation(.easeOut(duration: 0.15)) { window.moveTab(id, to: tab.id) }
                return true
            } isTargeted: { isTargeted in
                if isTargeted {
                    dropTargetID.wrappedValue = tab.id
                } else if dropTargetID.wrappedValue == tab.id {
                    dropTargetID.wrappedValue = nil
                }
            }
    }
}

/// Aba na grade: só o ícone do site, num bloco.
private struct GridTile: View {
    let tab: Tab
    let isActive: Bool
    let isDropTarget: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        TabIcon(tab: tab, size: 18)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Theme.surface : (isHovering ? Theme.surfaceHover : Theme.groupedCard))
                    .shadow(color: .black.opacity(isActive ? 0.07 : 0), radius: 1.5, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: isDropTarget ? 2 : 0)
            }
            .overlay(alignment: .topTrailing) {
                // Ponto vermelho: a página está usando a câmera ou o microfone.
                if tab.isCapturing {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .padding(5)
                        .accessibilityLabel("Using camera or microphone")
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture(perform: select)
            .onHover { isHovering = $0 }
            .help(tab.displayTitle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: tab.displayTitle))
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, select)
    }
}

struct SidebarToggleButton: View {
    let window: BrowserWindow

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { window.isSidebarVisible.toggle() }
        } label: {
            Label(
                window.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                systemImage: "sidebar.left"
            )
        }
        .buttonStyle(.chrome)
        .help(window.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
    }
}

private struct TabRow: View {
    let tab: Tab
    let isActive: Bool
    let isDropTarget: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            TabIcon(tab: tab)
            Text(verbatim: tab.displayTitle)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            TabMediaIndicators(tab: tab)
            Button(action: close) {
                Label("Close Tab", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering || isActive ? 1 : 0)
            .help("Close Tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(isActive ? Theme.surface : (isHovering ? Theme.surface.opacity(0.5) : .clear))
                .shadow(color: .black.opacity(isActive ? 0.07 : 0), radius: 1.5, y: 1)
        }
        .overlay(alignment: .top) {
            // Linha que indica onde a aba arrastada vai entrar.
            if isDropTarget {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .offset(y: -2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .help(tab.displayURL.isEmpty ? tab.displayTitle : tab.displayURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tab.displayTitle))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityAction(named: "Close Tab", close)
    }
}

private struct TabIcon: View {
    let tab: Tab
    var size: CGFloat = 16

    var body: some View {
        Group {
            if tab.isLoading && tab.favicon == nil {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// No lugar do seletor de perfis, numa janela privada.
private struct PrivateBrowsingBadge: View {
    var body: some View {
        Label("Private Browsing", systemImage: "eye.slash")
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: 12))
            .help("Private Browsing: no history, and cookies and site data are forgotten when the window closes.")
    }
}
