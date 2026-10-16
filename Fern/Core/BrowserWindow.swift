import AppKit
import Foundation
import Observation
import WebKit

/// Lembra quais perfis já tiveram a sessão restaurada nesta execução do app, para que
/// uma segunda janela não abra as mesmas abas de novo.
@MainActor
final class SessionRestoreTracker {
    static let shared = SessionRestoreTracker()
    var restoredProfiles: Set<Profile.ID> = []
}

/// Estado de uma janela: perfil em uso, abas de cada perfil, aba ativa e a interface que
/// não pertence a uma aba (pedido de foco na barra de endereço, barra de busca na página).
@MainActor
@Observable
final class BrowserWindow {
    /// Uma aba fechada, guardada para ⌘⇧T.
    private struct ClosedTab {
        let url: URL
        let index: Int
        let section: Tab.Section
        let profileID: Profile.ID
    }

    private static let closedTabsLimit = 20

    /// Perfil em uso. Trocar de perfil troca as abas exibidas; as do outro perfil ficam
    /// guardadas nesta janela.
    private(set) var profileID: Profile.ID
    private var tabsByProfile: [Profile.ID: [Tab]] = [:]
    private var activeTabIDByProfile: [Profile.ID: Tab.ID] = [:]

    /// Abas do perfil em uso, na ordem das seções: grade (ícones no topo da barra
    /// lateral), fixadas (cards no topo do cartão de abas) e as demais.
    private(set) var tabs: [Tab] {
        get { tabsByProfile[profileID] ?? [] }
        set { tabsByProfile[profileID] = newValue }
    }

    private(set) var activeTabID: Tab.ID {
        get { activeTabIDByProfile[profileID] ?? tabs[0].id }
        set { activeTabIDByProfile[profileID] = newValue }
    }

    var isSidebarVisible = true
    var isHistoryVisible = false
    var isBookmarksVisible = false
    /// Inspetor do Fern (F12), embaixo da página.
    var isDevToolsVisible = false
    @ObservationIgnored private var devToolsSessions: [Tab.ID: DevToolsSession] = [:]
    /// Muda a cada pedido para abrir o balão da estrela (⌘D) na barra de endereço.
    private(set) var bookmarkEditorRequest = 0
    /// Muda a cada pedido para mostrar a lista de downloads (⌥⌘L ou um download novo).
    private(set) var downloadsRequest = 0
    /// Direção da última troca de perfil, para a animação da barra lateral.
    private(set) var lastProfileSwitchWasForward = true

    /// Muda a cada pedido de foco na barra de endereço (⌘L). A `AddressBar` observa.
    private(set) var addressBarFocusRequest = 0

    private(set) var isFindBarVisible = false
    private(set) var findBarFocusRequest = 0
    var findQuery = ""
    /// `nil` enquanto não houve busca para o texto atual.
    private(set) var findMatched: Bool?

    @ObservationIgnored private var closedTabs: [ClosedTab] = []
    private(set) var canReopenClosedTab = false

    /// Janela privada: cookies e dados de sites só na memória (somem ao fechar), sem
    /// histórico, sem sessão salva e sem gravar a grade nem as fixadas.
    let isPrivate: Bool

    @ObservationIgnored let profiles: ProfileStore
    @ObservationIgnored let history: HistoryStore
    @ObservationIgnored let bookmarks: BookmarkStore
    /// Decisões de câmera e microfone. Numa janela privada, só na memória.
    @ObservationIgnored let sitePermissions: SitePermissionStore
    @ObservationIgnored private let storage: BrowserStorage
    @ObservationIgnored private let restoresSession: Bool
    /// Armazenamento só em memória, compartilhado pelas abas desta janela privada.
    @ObservationIgnored private let privateDataStore: WKWebsiteDataStore?
    @ObservationIgnored private let restoreTracker: SessionRestoreTracker
    @ObservationIgnored private var saveSessionTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// - Parameter restoresSession: reabre as abas da última vez ("continuar de onde
    ///   parou"). Cada perfil é restaurado uma vez por execução do app.
    init(
        isPrivate: Bool = false,
        profiles: ProfileStore = .shared,
        history: HistoryStore = .shared,
        bookmarks: BookmarkStore = .shared,
        sitePermissions: SitePermissionStore? = nil,
        storage: BrowserStorage = .standard,
        restoresSession: Bool = BrowserSettings.restoresSession,
        restoreTracker: SessionRestoreTracker = .shared
    ) {
        self.isPrivate = isPrivate
        self.profiles = profiles
        self.history = history
        self.bookmarks = bookmarks
        self.sitePermissions = sitePermissions ?? (isPrivate ? .inMemory() : .shared)
        self.storage = storage
        self.restoresSession = restoresSession && !isPrivate
        self.restoreTracker = restoreTracker
        privateDataStore = isPrivate ? .nonPersistent() : nil
        profileID = isPrivate ? Profile.defaultID : profiles.lastUsedProfileID
        loadTabs(for: profileID)
        activeTab.loadIfNeeded()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: ProfileStore.didDeleteProfile, object: nil, queue: .main) {
                [weak self] notification in
                guard let id = notification.object as? Profile.ID else { return }
                MainActor.assumeIsolated { self?.profileWasDeleted(id) }
            },
            center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.saveSessionNow() }
            },
        ]
    }

    var activeTab: Tab {
        tabs.first { $0.id == activeTabID } ?? tabs[0]
    }

    var gridTabs: [Tab] { tabs.filter(\.isInGrid) }
    var pinnedTabs: [Tab] { tabs.filter(\.isPinned) }
    var regularTabs: [Tab] { tabs.filter { !$0.isSaved } }

    var profile: Profile {
        profiles.profile(profileID)
            ?? Profile(id: Profile.defaultID, name: String(localized: "Personal"), color: .blue)
    }

    private var activeIndex: Int {
        tabs.firstIndex { $0.id == activeTabID } ?? 0
    }

    /// Posição logo depois da última aba de `section` (ou antes da primeira seção seguinte).
    private func endIndex(of section: Tab.Section) -> Int {
        tabs.firstIndex { $0.section > section } ?? tabs.count
    }

    private func startIndex(of section: Tab.Section) -> Int {
        tabs.firstIndex { $0.section >= section } ?? tabs.count
    }

    // MARK: - Perfis

    func switchProfile(to id: Profile.ID) {
        guard !isPrivate, id != profileID, profiles.profile(id) != nil else { return }
        let previous = profileID
        let order = profiles.profiles.map(\.id)
        lastProfileSwitchWasForward = (order.firstIndex(of: id) ?? 0) >= (order.firstIndex(of: previous) ?? 0)
        saveSessionNow()
        if isFindBarVisible { hideFindBar() }
        if tabsByProfile[id] == nil { loadTabs(for: id) }
        profileID = id
        if !profiles.isDraft(id) { profiles.lastUsedProfileID = id }
        select(activeTabID)
        discardDraftIfUnused(previous)
    }

    /// Gesto para a esquerda na barra lateral: vai para o próximo perfil. Depois do
    /// último, cria um perfil rascunho.
    func switchToNextProfile() {
        guard !isPrivate else { return }
        let order = profiles.profiles.map(\.id)
        guard let index = order.firstIndex(of: profileID) else { return }
        if index + 1 < order.count {
            switchProfile(to: order[index + 1])
        } else if !profiles.isDraft(profileID) {
            switchProfile(to: profiles.createDraft().id)
        }
    }

    /// Gesto para a direita: volta para o perfil anterior.
    func switchToPreviousProfile() {
        let order = profiles.profiles.map(\.id)
        guard let index = order.firstIndex(of: profileID), index > 0 else { return }
        switchProfile(to: order[index - 1])
    }

    /// Um rascunho em que nenhuma página foi aberta some ao sair dele.
    private func discardDraftIfUnused(_ id: Profile.ID) {
        guard profiles.isDraft(id) else { return }
        let used = tabsByProfile[id]?.contains { $0.currentOrDeferredURL != nil } ?? false
        if !used { profiles.delete(id) }
    }

    /// Monta as abas de um perfil: fixadas (sem carregar) e, se for o caso, a última sessão.
    private func loadTabs(for profile: Profile.ID) {
        var loaded: [Tab] = []
        for section in [Tab.Section.grid, .pinned] where !isPrivate {
            for url in storage.savedURLs(section, for: profile) {
                let saved = makeTab(profile: profile, deferredURL: url)
                saved.setSection(section)
                loaded.append(saved)
            }
        }

        var active: Tab?
        if restoresSession, restoreTracker.restoredProfiles.insert(profile).inserted,
            let session = storage.session(for: profile)
        {
            // Só a aba ativa carrega agora; as outras, quando forem abertas.
            for (index, url) in session.urls.enumerated() {
                let tab = makeTab(profile: profile, deferredURL: url)
                loaded.append(tab)
                if index == session.activeIndex { active = tab }
            }
        }
        if !loaded.contains(where: { !$0.isSaved }) {
            loaded.append(makeTab(profile: profile))
        }
        let selected = active ?? loaded.first { !$0.isSaved } ?? loaded[0]

        for tab in loaded { tab.browserWindow = self }
        tabsByProfile[profile] = loaded
        activeTabIDByProfile[profile] = selected.id
    }

    private func profileWasDeleted(_ id: Profile.ID) {
        tabsByProfile[id]?.forEach { $0.close() }
        tabsByProfile[id] = nil
        activeTabIDByProfile[id] = nil
        closedTabs.removeAll { $0.profileID == id }
        canReopenClosedTab = closedTabs.contains { $0.profileID == profileID }
        if profileID == id {
            profileID = Profile.defaultID
            if tabsByProfile[profileID] == nil { loadTabs(for: profileID) }
            select(activeTabID)
        }
    }

    /// Cria uma aba do perfil, com o armazenamento em memória se a janela for privada.
    private func makeTab(
        profile: Profile.ID, configuration: WKWebViewConfiguration? = nil, deferredURL: URL? = nil
    ) -> Tab {
        Tab(profile: profile, dataStore: privateDataStore, configuration: configuration, deferredURL: deferredURL)
    }

    // MARK: - Histórico e downloads

    /// Chamado pelas abas quando uma página termina de carregar.
    func tabDidFinishLoading(_ tab: Tab) {
        guard !isPrivate, let url = tab.url else { return }
        history.recordVisit(url: url, title: tab.title, profile: tab.profileID)
    }

    func tabTitleDidChange(_ tab: Tab) {
        guard !isPrivate, let url = tab.url else { return }
        history.updateTitle(tab.title, for: url, profile: tab.profileID)
    }

    func showDownloads() {
        downloadsRequest += 1
    }

    // MARK: - Inspetor

    func devTools(for tab: Tab) -> DevToolsSession {
        if let session = devToolsSessions[tab.id] { return session }
        let session = DevToolsSession()
        devToolsSessions[tab.id] = session
        return session
    }

    func tabDidStartNavigation(_ tab: Tab) {
        devToolsSessions[tab.id]?.pageDidChange()
    }

    // MARK: - Favoritos

    /// ⌘D: salva a página atual nos Favoritos (se ainda não for) e abre o balão para
    /// renomear ou remover.
    func bookmarkActiveTab() {
        guard let url = activeTab.url, ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        bookmarks.add(url: url, title: activeTab.title, profile: profileID)
        bookmarkEditorRequest += 1
    }

    /// Abre um favorito na aba atual, ou numa aba nova.
    func open(_ bookmark: Bookmark, inNewTab: Bool = false) {
        guard let url = bookmark.url else { return }
        if inNewTab || activeTab.isSaved {
            newTab(url: url)
        } else {
            activeTab.load(url)
            activeTab.focusPage()
        }
    }

    // MARK: - Sessão

    /// Chamado pelas abas quando a página muda, para salvar a sessão.
    func tabDidNavigate() {
        guard !isPrivate else { return }
        // Abrir uma página num perfil rascunho o torna um perfil de verdade.
        if profiles.isDraft(profileID), tabs.contains(where: { $0.currentOrDeferredURL != nil }) {
            profiles.commitDraft(profileID)
            profiles.lastUsedProfileID = profileID
        }
        scheduleSessionSave()
    }

    /// Salva logo depois de uma rajada de mudanças, não a cada uma.
    private func scheduleSessionSave() {
        saveSessionTask?.cancel()
        saveSessionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveSessionNow()
        }
    }

    /// Salva as abas abertas (não fixadas) de cada perfil desta janela. Com várias
    /// janelas, vale a que salvou por último.
    func saveSessionNow() {
        saveSessionTask?.cancel()
        guard !isPrivate else { return }
        for (profile, profileTabs) in tabsByProfile where !profiles.isDraft(profile) {
            var session = BrowserStorage.Session(urls: [], activeIndex: nil)
            for tab in profileTabs where !tab.isSaved {
                guard let url = tab.currentOrDeferredURL else { continue }
                if tab.id == activeTabIDByProfile[profile] { session.activeIndex = session.urls.count }
                session.urls.append(url)
            }
            storage.saveSession(session, for: profile)
        }
    }

    // MARK: - Abas

    /// Abre uma aba logo abaixo da ativa (ou no início das comuns, se a ativa está na grade
    /// ou fixada).
    ///
    /// - Parameters:
    ///   - url: página a carregar. `nil` abre uma aba em branco com foco no endereço.
    ///   - configuration: configuração recebida do WebKit ao abrir um link com
    ///     `target="_blank"`. Precisa ser usada como está para manter o `window.opener`.
    ///   - activate: `false` abre em segundo plano (⌘+clique).
    @discardableResult
    func newTab(url: URL? = nil, configuration: WKWebViewConfiguration? = nil, activate: Bool = true) -> Tab {
        let tab = makeTab(profile: profileID, configuration: configuration)
        insert(tab, at: tabs.isEmpty ? 0 : max(activeIndex + 1, startIndex(of: .regular)))
        if let url { tab.load(url) }
        if activate { select(tab.id) }
        scheduleSessionSave()
        return tab
    }

    func select(_ id: Tab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        findMatched = nil
        activeTab.loadIfNeeded()
        scheduleSessionSave()
        if activeTab.isBlank {
            focusAddressBar()
        } else {
            activeTab.focusPage()
        }
    }

    /// ⌘1…⌘8 vão para a aba nessa posição; ⌘9 vai sempre para a última.
    func selectTab(number: Int) {
        guard !tabs.isEmpty, number >= 1 else { return }
        let index = number >= 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        select(tabs[index].id)
    }

    func selectNextTab() {
        guard tabs.count > 1 else { return }
        select(tabs[(activeIndex + 1) % tabs.count].id)
    }

    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        select(tabs[(activeIndex - 1 + tabs.count) % tabs.count].id)
    }

    /// Fecha a aba. Retorna `false` se ela é a única: quem chamou deve fechar a janela.
    @discardableResult
    func closeTab(_ id: Tab.ID) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        let tab = tabs[index]
        if let url = tab.savedURL ?? tab.currentOrDeferredURL, url.absoluteString != "about:blank" {
            closedTabs.append(ClosedTab(url: url, index: index, section: tab.section, profileID: profileID))
            closedTabs = closedTabs.suffix(Self.closedTabsLimit)
            canReopenClosedTab = true
        }
        let wasActive = id == activeTabID
        tab.close()
        devToolsSessions[id] = nil
        tabs.remove(at: index)
        if tab.isSaved { saveSavedTabs() }
        scheduleSessionSave()
        if wasActive {
            // Como no Safari: vai para a aba que estava abaixo; se era a última, a de cima.
            select(tabs[min(index, tabs.count - 1)].id)
        }
        return true
    }

    func closeOtherTabs(than id: Tab.ID) {
        for tab in tabs where tab.id != id {
            closeTab(tab.id)
        }
        select(id)
    }

    func reopenClosedTab() {
        guard let closedIndex = closedTabs.lastIndex(where: { $0.profileID == profileID }) else { return }
        let closed = closedTabs.remove(at: closedIndex)
        canReopenClosedTab = closedTabs.contains { $0.profileID == profileID }
        let tab = makeTab(profile: profileID)
        let index = min(max(closed.index, startIndex(of: closed.section)), endIndex(of: closed.section))
        insert(tab, at: index)
        tab.load(closed.url)
        if closed.section != .regular {
            tab.setSection(closed.section)
            saveSavedTabs()
        }
        select(tab.id)
    }

    // MARK: - Grade, fixar e reordenar

    /// Fixa a aba como card no topo do cartão de abas, ou desafixa.
    func togglePin(_ id: Tab.ID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        move(id, to: tab.isPinned ? .regular : .pinned)
    }

    /// Põe a aba na grade de ícones, ou tira de lá.
    func toggleGrid(_ id: Tab.ID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        move(id, to: tab.isInGrid ? .regular : .grid)
    }

    /// Leva a aba para o fim de `section` (ou para o início das comuns, ao desafixar).
    /// Abas em branco não podem ir para a grade nem ser fixadas.
    private func move(_ id: Tab.ID, to section: Tab.Section) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        guard section == .regular || !tab.isBlank else { return }
        tabs.remove(at: index)
        tab.setSection(section)
        tabs.insert(tab, at: section == .regular ? startIndex(of: .regular) : endIndex(of: section))
        saveSavedTabs()
        scheduleSessionSave()
    }

    func moveTabs(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        scheduleSessionSave()
    }

    /// Arrastar e soltar na barra lateral: a aba arrastada assume a posição de `target` e
    /// passa para a seção dele (soltar sobre um ícone da grade põe a aba na grade, etc.).
    func moveTab(_ id: Tab.ID, to target: Tab.ID) {
        guard id != target, let from = tabs.firstIndex(where: { $0.id == id }),
            let to = tabs.firstIndex(where: { $0.id == target })
        else { return }
        let tab = tabs[from]
        let targetSection = tabs[to].section
        let sectionChanged = tab.section != targetSection
        if sectionChanged {
            guard targetSection == .regular || !tab.isBlank else { return }
            tab.setSection(targetSection)
        }
        tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        if sectionChanged || targetSection != .regular { saveSavedTabs() }
        scheduleSessionSave()
    }

    private func insert(_ tab: Tab, at index: Int) {
        tab.browserWindow = self
        tabs.insert(tab, at: index)
    }

    private func saveSavedTabs() {
        guard !isPrivate else { return }
        storage.saveURLs(gridTabs.compactMap(\.savedURL), .grid, for: profileID)
        storage.saveURLs(pinnedTabs.compactMap(\.savedURL), .pinned, for: profileID)
    }

    // MARK: - Barra de endereço

    func focusAddressBar() {
        addressBarFocusRequest += 1
    }

    /// Interpreta o texto digitado e carrega na aba ativa. Retorna se havia algo a abrir.
    @discardableResult
    func submitAddress(_ text: String) -> Bool {
        let parser = AddressBarParser(searchEngine: BrowserSettings.searchEngine)
        guard let result = parser.parse(text) else { return false }
        activeTab.load(result.url)
        activeTab.focusPage()
        return true
    }

    // MARK: - Busca na página

    func showFindBar() {
        isFindBarVisible = true
        findBarFocusRequest += 1
    }

    func hideFindBar() {
        isFindBarVisible = false
        findMatched = nil
        activeTab.focusPage()
    }

    func findNext() async {
        await find(backwards: false)
    }

    func findPrevious() async {
        await find(backwards: true)
    }

    private func find(backwards: Bool) async {
        guard !findQuery.isEmpty else {
            findMatched = nil
            return
        }
        if !isFindBarVisible { showFindBar() }
        let query = findQuery
        let matched = await activeTab.find(query, backwards: backwards)
        // Ignora respostas de buscas antigas se o usuário continuou digitando.
        if query == findQuery { findMatched = matched }
    }
}
