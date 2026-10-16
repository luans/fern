import SwiftUI

/// Barra de busca na página (⌘F). Enter vai para a próxima ocorrência, Esc fecha.
struct FindBar: View {
    @Bindable var window: BrowserWindow
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find on page", text: $window.findQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .focused($isFocused)
                .onSubmit { Task { await window.findNext() } }
                .onExitCommand { window.hideFindBar() }

            if window.findMatched == false {
                Text("Not found")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ControlGroup {
                Button {
                    Task { await window.findPrevious() }
                } label: {
                    Label("Previous match", systemImage: "chevron.up")
                }
                .help("Previous match")
                Button {
                    Task { await window.findNext() }
                } label: {
                    Label("Next match", systemImage: "chevron.down")
                }
                .help("Next match")
            }
            .fixedSize()
            .disabled(window.findQuery.isEmpty)

            Button("Done") { window.hideFindBar() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .onAppear { isFocused = true }
        .onChange(of: window.findBarFocusRequest) { isFocused = true }
        .onChange(of: window.findQuery) { Task { await window.findNext() } }
    }
}
