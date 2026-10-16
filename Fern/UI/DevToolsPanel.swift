import SwiftUI

/// Inspetor do Fern (F12 ou ⌥⌘I), encaixado embaixo da página.
struct DevToolsPanel: View {
    enum Section: String, CaseIterable, Identifiable {
        case elements, console, network
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .elements: "Elements"
            case .console: "Console"
            case .network: "Network"
            }
        }
    }

    let window: BrowserWindow
    let tab: Tab

    @AppStorage("devToolsSection") private var section = Section.console
    @State private var showsSource = false
    @State private var isShowingAbout = false

    private var session: DevToolsSession { window.devTools(for: tab) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch section {
                case .elements: ElementsView(session: session, tab: tab, showsSource: showsSource)
                case .console: ConsoleView(session: session, tab: tab)
                case .network: NetworkView(session: session, tab: tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Developer Tools")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if section == .elements {
                Toggle("Source", isOn: $showsSource)
                    .toggleStyle(.button)
                    .controlSize(.small)
            }

            Spacer()

            switch section {
            case .elements:
                Button("Refresh") { Task { await refreshElements() } }
                    .controlSize(.small)
            case .console:
                Button("Clear") { session.clearConsole() }
                    .controlSize(.small)
            case .network:
                Button("Refresh") { Task { await session.loadNetwork(from: tab.webView) } }
                    .controlSize(.small)
            }

            Button {
                isShowingAbout.toggle()
            } label: {
                Label("About the Inspector", systemImage: "info.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("About the Inspector")
            .popover(isPresented: $isShowingAbout, arrowEdge: .bottom) {
                Text(
                    "This is Fern's own inspector. For WebKit's full Web Inspector (styles, debugger, storage), open Safari, enable Develop in Settings › Advanced, then choose Develop › this Mac › Fern and the page."
                )
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 320)
            }

            Button {
                window.isDevToolsVisible = false
            } label: {
                Label("Close Developer Tools", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Close Developer Tools")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func refreshElements() async {
        if showsSource {
            await session.loadHTML(from: tab.webView)
        } else {
            await session.loadDOM(from: tab.webView)
        }
    }
}

// MARK: - Elementos

private struct ElementsView: View {
    let session: DevToolsSession
    let tab: Tab
    let showsSource: Bool

    var body: some View {
        Group {
            if showsSource {
                ScrollView([.vertical, .horizontal]) {
                    Text(verbatim: session.html ?? "")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            } else if let root = session.dom {
                List([root], children: \.children) { node in
                    Text(verbatim: node.label)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(node.isText ? .secondary : .primary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .listStyle(.plain)
            } else {
                Text("No page loaded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(tab.id)-\(showsSource)-\(tab.url?.absoluteString ?? "")") {
            if showsSource {
                await session.loadHTML(from: tab.webView)
            } else {
                await session.loadDOM(from: tab.webView)
            }
        }
    }
}

// MARK: - Console

private struct ConsoleView: View {
    let session: DevToolsSession
    let tab: Tab

    @State private var input = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(session.console) { entry in
                            ConsoleRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .onChange(of: session.console.last?.id) {
                    if let last = session.console.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                }
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                TextField("Run JavaScript on this page", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($isInputFocused)
                    .onSubmit(run)
                    .accessibilityLabel("JavaScript")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        // Enquanto o console está aberto, busca as mensagens novas da página.
        .task(id: tab.id) {
            while !Task.isCancelled {
                await session.pollConsole(in: tab.webView)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        .onAppear { isInputFocused = true }
    }

    private func run() {
        let code = input
        input = ""
        Task { await session.evaluate(code, in: tab.webView) }
    }
}

private struct ConsoleRow: View {
    let entry: DevToolsSession.ConsoleEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 12)
                .accessibilityHidden(true)
            Text(verbatim: entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(entry.kind == .result ? .secondary : color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(background)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private var symbol: String {
        switch entry.kind {
        case .input: "chevron.right"
        case .result: "chevron.left"
        case .warn: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        case .log, .debug: "circle.fill"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .warn: .orange
        case .error: .red
        case .input: .accentColor
        case .debug: .secondary
        case .log, .info, .result: .primary
        }
    }

    private var background: Color {
        switch entry.kind {
        case .warn: .orange.opacity(0.08)
        case .error: .red.opacity(0.08)
        default: .clear
        }
    }
}

// MARK: - Rede

private struct NetworkView: View {
    let session: DevToolsSession
    let tab: Tab

    var body: some View {
        Table(session.network) {
            TableColumn("Name") { entry in
                Text(verbatim: entry.name)
                    .help(entry.url)
            }
            TableColumn("Type") { entry in
                Text(verbatim: entry.type)
            }
            .width(min: 60, ideal: 80, max: 120)
            TableColumn("Size") { entry in
                // 0 em recursos vindos do cache ou de outros sites sem permissão de medir.
                Text(verbatim: entry.size > 0 ? Int64(entry.size).formatted(.byteCount(style: .file)) : "–")
            }
            .width(min: 60, ideal: 80, max: 120)
            TableColumn("Time") { entry in
                Text(verbatim: "\(Int(entry.duration.rounded())) ms")
            }
            .width(min: 60, ideal: 70, max: 100)
        }
        .font(.system(size: 11))
        // Atualiza a lista enquanto a aba Rede está aberta.
        .task(id: tab.id) {
            while !Task.isCancelled {
                await session.loadNetwork(from: tab.webView)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
