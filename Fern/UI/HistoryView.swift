import SwiftUI

/// Histórico do perfil em uso (⌘Y): busca, entradas agrupadas por dia e limpeza por
/// período. Clicar numa entrada abre a página numa nova aba.
struct HistoryView: View {
    let window: BrowserWindow

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var history: HistoryStore { window.history }

    private var days: [(day: Date, entries: [HistoryEntry])] {
        _ = history.revision
        let entries = history.entries(profile: window.profileID, matching: query, limit: 500)
        let grouped = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.lastVisited) }
        return grouped.keys.sorted(by: >).map { (day: $0, entries: grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("History")
                    .font(.title3.weight(.semibold))
                Spacer()
                TextField("Search History", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Menu("Clear") {
                    ForEach(ClearPeriod.allCases) { period in
                        Button(String(localized: period.title)) {
                            history.clear(profile: window.profileID, since: period.startDate())
                        }
                    }
                }
                .fixedSize()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            if days.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No History" : "No Results",
                    systemImage: "clock",
                    description: Text(
                        window.isPrivate
                            ? "Private windows don't save history." : "Pages you visit will appear here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(days, id: \.day) { day in
                        Section(day.day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                            ForEach(day.entries) { entry in
                                HistoryRow(entry: entry) { open(entry) }
                                    .contextMenu {
                                        Button("Open in New Tab") { open(entry) }
                                        Button("Copy Link") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(entry.urlString, forType: .string)
                                        }
                                        Divider()
                                        Button("Delete from History") { history.delete(entry) }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 620, height: 520)
    }

    private func open(_ entry: HistoryEntry) {
        guard let url = entry.url else { return }
        window.newTab(url: url)
        dismiss()
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.displayTitle)
                        .lineLimit(1)
                    Text(verbatim: entry.url?.host() ?? entry.urlString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(entry.lastVisited, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.urlString)
    }
}
