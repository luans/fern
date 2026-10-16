import SwiftUI

struct AddressBar: View {
    let window: BrowserWindow
    let tab: Tab

    @State private var text = ""
    @FocusState private var isFocused: Bool
    @State private var suggestions: [AddressSuggestion] = []
    /// Sugestão escolhida com as setas; `nil` faz o Enter abrir o texto digitado.
    @State private var selectedSuggestion: Int?

    var body: some View {
        HStack(spacing: 6) {
            SecurityIndicator(state: tab.securityState)

            TextField("Search or enter website name", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .autocorrectionDisabled()
                .onSubmit(submit)
                .onExitCommand(perform: cancelEditing)
                .onKeyPress(.downArrow) { moveSelection(by: 1) }
                .onKeyPress(.upArrow) { moveSelection(by: -1) }
                .accessibilityLabel("Address and search")
                .accessibilityIdentifier("addressBar")

            BookmarkButton(window: window, tab: tab)
            SiteSettingsButton(window: window, tab: tab)
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.controlSize)
        .background(
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        )
        .overlay(alignment: .topLeading) {
            if !suggestions.isEmpty {
                SuggestionList(suggestions: suggestions, selected: selectedSuggestion) { suggestion in
                    open(suggestion)
                }
                .offset(y: Theme.controlSize + 6)
            }
        }
        .onChange(of: text) {
            updateSuggestions()
        }
        .onAppear {
            text = tab.displayURL
            if tab.isBlank { requestFocus() }
        }
        .onChange(of: tab.url) {
            if !isFocused { text = tab.displayURL }
        }
        .onChange(of: tab.id) {
            text = tab.displayURL
        }
        .onChange(of: isFocused) {
            // Ao sair da edição sem enviar, volta a mostrar a URL da página. Espera um
            // instante para um clique numa sugestão chegar antes de a lista sumir.
            guard !isFocused else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !isFocused else { return }
                text = tab.displayURL
                suggestions = []
            }
        }
        .onChange(of: window.addressBarFocusRequest) {
            requestFocus()
        }
    }

    private func submit() {
        if let index = selectedSuggestion, suggestions.indices.contains(index) {
            open(suggestions[index])
        } else if window.submitAddress(text) {
            isFocused = false
            suggestions = []
        }
    }

    private func open(_ suggestion: AddressSuggestion) {
        suggestions = []
        selectedSuggestion = nil
        isFocused = false
        window.open(suggestion)
    }

    private func updateSuggestions() {
        selectedSuggestion = nil
        // Só sugere enquanto o usuário edita o texto, não quando a barra mostra a URL.
        guard isFocused, text != tab.displayURL else {
            suggestions = []
            return
        }
        suggestions = window.suggestions(for: text)
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        let current = selectedSuggestion ?? -1
        let next = current + offset
        selectedSuggestion = next < 0 ? nil : min(next, suggestions.count - 1)
        return .handled
    }

    private func cancelEditing() {
        if !suggestions.isEmpty {
            suggestions = []
            selectedSuggestion = nil
            return
        }
        text = tab.displayURL
        isFocused = false
        tab.focusPage()
    }

    /// Só pede foco se a barra ainda não tem. Reaplicar o foco enquanto o usuário já
    /// está digitando faz o AppKit recriar o editor do campo e o texto digitado se perde.
    /// Ao abrir a janela, ela ainda não é a principal; por isso a nova tentativa.
    private func requestFocus() {
        guard !isFocused else { return }
        isFocused = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if !isFocused { isFocused = true }
        }
    }
}

private struct SecurityIndicator: View {
    let state: Tab.SecurityState

    var body: some View {
        switch state {
        case .secure:
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .help("Secure connection")
                .accessibilityLabel("Secure connection")
        case .insecure:
            Label("Not Secure", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .fixedSize()
                .help(
                    "This connection is not secure. Information you send or receive may be visible to others."
                )
        case .none:
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}

/// Lista de sugestões que aparece abaixo da barra de endereço.
private struct SuggestionList: View {
    let suggestions: [AddressSuggestion]
    let selected: Int?
    let open: (AddressSuggestion) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    open(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(verbatim: suggestion.title)
                            .lineLimit(1)
                        Text(verbatim: suggestion.url.host() ?? suggestion.url.absoluteString)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if suggestion.isOpenTab {
                            Text("Switch to Tab")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(index == selected ? Color.accentColor.opacity(0.18) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }
}

extension AddressSuggestion {
    fileprivate var isOpenTab: Bool {
        if case .openTab = kind { return true }
        return false
    }

    fileprivate var symbol: String {
        switch kind {
        case .openTab: "square.on.square"
        case .bookmark: "star"
        case .history: "clock"
        }
    }
}

/// Ajustes do site aberto: bloqueio de anúncios e permissões de câmera e microfone.
/// Fica vermelho, com os controles no topo, enquanto a página usa um dispositivo.
private struct SiteSettingsButton: View {
    let window: BrowserWindow
    let tab: Tab

    @State private var isShowingPopover = false
    private let blocker = ContentBlocker.shared

    var body: some View {
        if let host = ContentBlocker.normalizedHost(tab.url?.host()),
            ["http", "https"].contains(tab.url?.scheme?.lowercased())
        {
            Button {
                isShowingPopover.toggle()
            } label: {
                icon
            }
            .buttonStyle(.borderless)
            .help("Site Settings")
            .accessibilityLabel("Site Settings")
            .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
                SiteSettingsPopover(window: window, tab: tab, host: host)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if tab.cameraCaptureState == .active {
            Image(systemName: "video.fill").foregroundStyle(.red)
        } else if tab.microphoneCaptureState == .active {
            Image(systemName: "mic.fill").foregroundStyle(.red)
        } else if tab.isCapturing {
            Image(systemName: "mic.slash.fill").foregroundStyle(.secondary)
        } else if blocker.isEnabled {
            let isBlocking = blocker.isBlocking(on: tab.url)
            Image(systemName: isBlocking ? "shield.lefthalf.filled" : "shield.slash")
                .foregroundStyle(isBlocking ? Color.accentColor : .secondary)
        } else {
            Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
        }
    }
}

private struct SiteSettingsPopover: View {
    let window: BrowserWindow
    let tab: Tab
    let host: String

    private let blocker = ContentBlocker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: host)
                .font(.headline)

            if tab.isCapturing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In use")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    if tab.cameraCaptureState != .none {
                        Toggle(
                            isOn: Binding(
                                get: { tab.cameraCaptureState == .active }, set: { _ in tab.toggleCameraMuted() })
                        ) {
                            Label("Camera", systemImage: "video.fill")
                        }
                        .toggleStyle(.switch)
                    }
                    if tab.microphoneCaptureState != .none {
                        Toggle(
                            isOn: Binding(
                                get: { tab.microphoneCaptureState == .active },
                                set: { _ in tab.toggleMicrophoneMuted() })
                        ) {
                            Label("Microphone", systemImage: "mic.fill")
                        }
                        .toggleStyle(.switch)
                    }
                    Button("Stop Using Camera and Microphone", role: .destructive) { tab.stopCapture() }
                }
                Divider()
            }

            if blocker.isEnabled {
                Toggle(
                    isOn: Binding(
                        get: { blocker.isBlocking(on: tab.url) },
                        set: { blocking in
                            blocker.setBlocking(blocking, on: tab.url)
                            tab.reload()
                        })
                ) {
                    Text("Block ads and trackers")
                }
                .toggleStyle(.switch)
            }

            ForEach(CaptureDevice.allCases, id: \.self) { device in
                Picker(selection: binding(for: device)) {
                    ForEach(SitePermission.allCases, id: \.self) { permission in
                        Text(permission.title).tag(permission)
                    }
                } label: {
                    Label {
                        Text(device.title)
                    } icon: {
                        Image(systemName: device.symbol)
                    }
                }
            }

            Text(
                window.isPrivate
                    ? "In a private window, these choices are forgotten when it closes."
                    : "Changes apply the next time the site asks."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func binding(for device: CaptureDevice) -> Binding<SitePermission> {
        Binding(
            get: { window.sitePermissions.permission(device, host: host, profile: tab.profileID) },
            set: { window.sitePermissions.set($0, for: device, host: host, profile: tab.profileID) }
        )
    }
}
