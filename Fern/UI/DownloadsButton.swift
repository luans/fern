import SwiftUI

/// Botão de downloads no topo. Mostra o progresso enquanto há downloads e abre a lista
/// sozinho quando um download começa nesta janela (ou com ⌥⌘L).
struct DownloadsButton: View {
    let window: BrowserWindow

    @State private var isShowingList = false
    private let manager = DownloadManager.shared

    var body: some View {
        Button {
            isShowingList.toggle()
        } label: {
            Label {
                Text("Downloads")
            } icon: {
                if manager.hasActiveDownloads {
                    ProgressRing(progress: overallProgress)
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
        }
        .help("Downloads")
        .accessibilityIdentifier("downloadsButton")
        .popover(isPresented: $isShowingList, arrowEdge: .bottom) {
            DownloadsList(manager: manager)
        }
        .onChange(of: window.downloadsRequest) { isShowingList = true }
    }

    private var overallProgress: Double? {
        let active = manager.items.filter { $0.state == .inProgress }
        let known = active.compactMap(\.progress)
        guard !known.isEmpty, known.count == active.count else { return nil }
        return known.reduce(0, +) / Double(known.count)
    }
}

private struct ProgressRing: View {
    let progress: Double?

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.3), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress ?? 0.25)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}

private struct DownloadsList: View {
    let manager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads")
                    .font(.headline)
                Spacer()
                Button("Clear") { manager.clearFinished() }
                    .disabled(!manager.items.contains { $0.state != .inProgress })
            }
            .padding(12)

            Divider()

            if manager.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("No Downloads")
                        .font(.headline)
                    Text("Files you download will appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(manager.items) { item in
                            DownloadRow(item: item, manager: manager)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 340)
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    let manager: DownloadManager

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.filename.isEmpty ? "…" : item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                status
            }

            Spacer(minLength: 0)

            switch item.state {
            case .inProgress:
                Button {
                    manager.cancel(item)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            case .finished:
                Button {
                    manager.reveal(item)
                } label: {
                    Label("Show in Finder", systemImage: "magnifyingglass.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            case .failed, .cancelled:
                EmptyView()
            }
        }
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if item.state == .finished { manager.open(item) }
        }
        .contextMenu {
            Button("Open") { manager.open(item) }
                .disabled(item.state != .finished)
            Button("Show in Finder") { manager.reveal(item) }
                .disabled(item.state != .finished)
            if let source = item.sourceURL {
                Button("Copy Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(source.absoluteString, forType: .string)
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch item.state {
        case .inProgress:
            if let progress = item.progress {
                ProgressView(value: progress)
                    .controlSize(.small)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
        case .finished:
            Text(item.date, format: .dateTime.day().month().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message.isEmpty ? String(localized: "Failed") : message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        case .cancelled:
            Text("Cancelled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var icon: NSImage {
        if let destination = item.destination, FileManager.default.fileExists(atPath: destination.path) {
            return NSWorkspace.shared.icon(forFile: destination.path)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}
