import SwiftUI

extension ProfileColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .gray: .gray
        }
    }

    var localizedName: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .teal: String(localized: "Teal")
        case .gray: String(localized: "Gray")
        }
    }
}

/// Círculo com a inicial do perfil, na cor dele.
struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 20

    var body: some View {
        Text(verbatim: profile.initial)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(profile.color.color.gradient))
            .accessibilityHidden(true)
    }
}

/// Rodapé da barra lateral: troca de perfil. O ativo aparece com o nome; os outros,
/// como bolinhas coloridas. O + cria um perfil novo.
struct ProfileSwitcher: View {
    let window: BrowserWindow

    @State private var isCreating = false
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsView.selectedTabKey) private var settingsTab = SettingsView.Tab.general

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(window.profiles.profiles) { profile in
                        ProfileChip(
                            profile: profile,
                            isActive: profile.id == window.profileID,
                            isDraft: window.profiles.isDraft(profile.id)
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) { window.switchProfile(to: profile.id) }
                        }
                        .contextMenu {
                            Button("Manage Profiles…") {
                                settingsTab = .profiles
                                openSettings()
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            Divider()
                .frame(height: 16)

            Button {
                isCreating = true
            } label: {
                Label("New Profile", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Profile")
            .popover(isPresented: $isCreating, arrowEdge: .top) {
                ProfileForm(title: "New Profile", confirmTitle: "Create") { name, color in
                    let profile = window.profiles.add(name: name, color: color)
                    window.switchProfile(to: profile.id)
                    isCreating = false
                } cancel: {
                    isCreating = false
                }
            }
        }
        .padding(4)
        .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profiles")
        .accessibilityIdentifier("profileSwitcher")
    }
}

private struct ProfileChip: View {
    let profile: Profile
    let isActive: Bool
    /// Rascunho: aparece com borda tracejada até ser usado.
    let isDraft: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(profile.color.color)
                .frame(width: 8, height: 8)
            if isActive {
                Text(verbatim: profile.name)
                    .font(.system(size: 12, weight: .medium))
                    .italic(isDraft)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, isActive ? 10 : 0)
        .frame(minWidth: 28, minHeight: 28)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Theme.surface : (isHovering ? Theme.surface.opacity(0.5) : .clear))
                .shadow(color: .black.opacity(isActive ? 0.07 : 0), radius: 1.5, y: 1)
        }
        .overlay {
            if isDraft {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .help(profile.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: profile.name))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
    }
}

/// Nome e cor de um perfil. Usado para criar perfis.
struct ProfileForm: View {
    let title: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let confirm: (String, ProfileColor) -> Void
    let cancel: () -> Void

    @State private var name = ""
    @State private var color: ProfileColor = .purple
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            TextField("Name", text: $name, prompt: Text("Work, Study…"))
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(submit)

            ProfileColorPicker(selection: $color)

            Text("Each profile keeps its own tabs, cookies and logins.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { isNameFocused = true }
    }

    private func submit() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        confirm(name, color)
    }
}

struct ProfileColorPicker: View {
    @Binding var selection: ProfileColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ProfileColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.6), lineWidth: selection == color ? 2 : 0)
                                .padding(-3)
                        }
                        .padding(3)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: color.localizedName))
                .help(Text(verbatim: color.localizedName))
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
    }
}

/// Avatar do perfil no canto superior direito. Abre uma lista para trocar de perfil.
struct ProfileMenuButton: View {
    let window: BrowserWindow

    @State private var isShowingPopover = false
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsView.selectedTabKey) private var settingsTab = SettingsView.Tab.general

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            Label {
                Text("Profile")
            } icon: {
                ProfileAvatar(profile: window.profile)
            }
        }
        .help(Text(verbatim: window.profile.name))
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(window.profiles.profiles) { profile in
                    Button {
                        window.switchProfile(to: profile.id)
                        isShowingPopover = false
                    } label: {
                        HStack(spacing: 10) {
                            ProfileAvatar(profile: profile, size: 26)
                            Text(verbatim: profile.name)
                            Spacer()
                            if profile.id == window.profileID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(profile.id == window.profileID ? .isSelected : [])
                }
                Divider()
                    .padding(.vertical, 4)
                Button("Manage Profiles…") {
                    isShowingPopover = false
                    settingsTab = .profiles
                    openSettings()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .padding(8)
            .frame(width: 240)
        }
    }
}
