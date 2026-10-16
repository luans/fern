import SwiftUI
import WebKit

struct SettingsView: View {
    enum Tab: String {
        case general, privacy, websites, profiles, experiments
    }

    /// Aba aberta nos Ajustes. Outras telas mudam este valor antes de abrir os Ajustes
    /// (ex.: "Gerenciar Perfis…").
    static let selectedTabKey = "settingsTab"

    @AppStorage(selectedTabKey) private var selectedTab = Tab.general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(Tab.privacy)
            WebsitesSettings()
                .tabItem { Label("Websites", systemImage: "globe") }
                .tag(Tab.websites)
            ProfilesSettings()
                .tabItem { Label("Profiles", systemImage: "person.2") }
                .tag(Tab.profiles)
            ExperimentsSettings()
                .tabItem { Label("Experiments", systemImage: "flask") }
                .tag(Tab.experiments)
        }
        .frame(width: 500)
    }
}

private struct GeneralSettings: View {
    @AppStorage(BrowserSettings.Key.searchEngine) private var searchEngine: SearchEngine = .default
    @AppStorage(BrowserSettings.Key.restoresSession) private var restoresSession = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $restoresSession) {
                    Text("Continue where you left off")
                    Text("When Fern opens, reopen the tabs from your last session.")
                }
            }
            Section {
                Picker("Search engine", selection: $searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(verbatim: engine.displayName).tag(engine)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProfilesSettings: View {
    private let store = ProfileStore.shared
    @State private var isCreating = false
    @State private var profilePendingDeletion: Profile?

    var body: some View {
        Form {
            Section {
                ForEach(store.profiles) { profile in
                    ProfileSettingsRow(profile: profile) {
                        profilePendingDeletion = profile
                    }
                }
            } footer: {
                Text("Each profile keeps its own tabs, cookies and logins.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("New Profile…") { isCreating = true }
                    .popover(isPresented: $isCreating, arrowEdge: .bottom) {
                        ProfileForm(title: "New Profile", confirmTitle: "Create") { name, color in
                            store.add(name: name, color: color)
                            isCreating = false
                        } cancel: {
                            isCreating = false
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { profilePendingDeletion != nil },
                set: { if !$0 { profilePendingDeletion = nil } }
            )
        ) {
            Button("Delete Profile", role: .destructive) {
                if let profile = profilePendingDeletion { store.delete(profile.id) }
                profilePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { profilePendingDeletion = nil }
        } message: {
            Text("Its tabs will close and its cookies, logins and site data will be removed from this Mac.")
        }
    }

    private var deletionTitle: Text {
        Text("Delete “\(profilePendingDeletion?.name ?? "")”?")
    }
}

private struct ProfileSettingsRow: View {
    let profile: Profile
    let delete: () -> Void

    @State private var name = ""

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(ProfileColor.allCases, id: \.self) { color in
                    Button {
                        ProfileStore.shared.update(profile.id, color: color)
                    } label: {
                        Label {
                            Text(verbatim: color.localizedName)
                        } icon: {
                            Image(systemName: profile.color == color ? "checkmark.circle.fill" : "circle.fill")
                        }
                    }
                }
            } label: {
                ProfileAvatar(profile: profile, size: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Color")

            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .onSubmit(commit)
                .onChange(of: name) { commit() }

            if profile.isDefault {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(role: .destructive, action: delete) {
                    Label("Delete Profile", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Delete Profile")
            }
        }
        .onAppear { name = profile.name }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != profile.name else { return }
        ProfileStore.shared.update(profile.id, name: trimmed)
    }
}

/// Uma chave por experimento (ver `Experiment`).
private struct ExperimentsSettings: View {
    var body: some View {
        Form {
            Section {
                ForEach(Experiment.allCases) { experiment in
                    ExperimentToggle(experiment: experiment)
                }
            } footer: {
                Text("Experiments are ideas being tried out in Fern. They may change or go away.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ExperimentToggle: View {
    let experiment: Experiment
    @AppStorage private var isEnabled: Bool

    init(experiment: Experiment) {
        self.experiment = experiment
        _isEnabled = AppStorage(wrappedValue: experiment.isEnabledByDefault, experiment.storageKey)
    }

    var body: some View {
        Toggle(isOn: $isEnabled) {
            Text(experiment.title)
            Text(experiment.summary)
        }
    }
}

private struct PrivacySettings: View {
    @AppStorage(BrowserSettings.Key.blocksContent) private var blocksContent = true
    private let blocker = ContentBlocker.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $blocksContent) {
                    Text("Block ads and trackers")
                    Text("Uses a list of known ad and tracking services. Changes apply as pages load.")
                }
            }
            if blocksContent && !blocker.allowedHosts.isEmpty {
                Section("Sites where blocking is off") {
                    ForEach(blocker.allowedHosts.sorted(), id: \.self) { host in
                        HStack {
                            Text(verbatim: host)
                            Spacer()
                            Button("Remove") { blocker.removeException(host) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            ClearBrowsingDataSection()
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Apaga histórico, cookies e dados de sites, e cache de um perfil, num período.
private struct ClearBrowsingDataSection: View {
    @State private var profileID = ProfileStore.shared.lastUsedProfileID
    @State private var period = ClearPeriod.allTime
    @State private var clearsHistory = true
    @State private var clearsSiteData = true
    @State private var clearsCache = true
    @State private var isConfirming = false
    @State private var isClearing = false
    @State private var didClear = false

    var body: some View {
        Section {
            Picker("Profile", selection: $profileID) {
                ForEach(ProfileStore.shared.profiles) { profile in
                    Text(verbatim: profile.name).tag(profile.id)
                }
            }
            Picker("Period", selection: $period) {
                ForEach(ClearPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            Toggle("History", isOn: $clearsHistory)
            Toggle("Cookies and site data", isOn: $clearsSiteData)
            Toggle("Cached images and files", isOn: $clearsCache)
            HStack {
                if didClear {
                    Label("Cleared", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear Browsing Data…") { isConfirming = true }
                    .disabled(isClearing || !(clearsHistory || clearsSiteData || clearsCache))
            }
        } header: {
            Text("Clear browsing data")
        } footer: {
            Text("Clearing cookies signs you out of websites in this profile.")
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Clear browsing data?", isPresented: $isConfirming) {
            Button("Clear", role: .destructive) { Task { await clear() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .onChange(of: profileID) { didClear = false }
        .onChange(of: period) { didClear = false }
    }

    private func clear() async {
        isClearing = true
        defer { isClearing = false }
        let since = period.startDate()
        if clearsHistory {
            HistoryStore.shared.clear(profile: profileID, since: since)
        }
        var types: Set<String> = []
        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
        ]
        if clearsCache { types.formUnion(cacheTypes) }
        if clearsSiteData { types.formUnion(WKWebsiteDataStore.allWebsiteDataTypes().subtracting(cacheTypes)) }
        if !types.isEmpty {
            await WebEngine.shared.dataStore(for: profileID).removeData(
                ofTypes: types, modifiedSince: since ?? .distantPast)
        }
        didClear = true
    }
}

/// Reprodução automática e permissões de câmera e microfone de cada site.
private struct WebsitesSettings: View {
    @AppStorage(BrowserSettings.Key.autoplay) private var autoplay = AutoplayPolicy.default
    private let store = SitePermissionStore.shared
    private let profiles = ProfileStore.shared

    var body: some View {
        Form {
            Section {
                Picker("Auto-play", selection: $autoplay) {
                    ForEach(AutoplayPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
            } footer: {
                Text("Applies to tabs opened after the change.")
                    .foregroundStyle(.secondary)
            }

            let profilesWithSites = profiles.profiles.filter { !store.sites(for: $0.id).isEmpty }
            if profilesWithSites.isEmpty {
                Section("Camera and microphone") {
                    Text("When a site asks to use the camera or microphone, your choice for it appears here.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(profilesWithSites) { profile in
                Section {
                    ForEach(store.sites(for: profile.id), id: \.host) { site in
                        SitePermissionsRow(host: site.host, profile: profile.id)
                    }
                } header: {
                    Text("Camera and microphone · \(profile.name)")
                }
            }

            Section {
                HStack {
                    Button("Camera Privacy Settings…") { CaptureDevice.camera.openSystemSettings() }
                    Button("Microphone Privacy Settings…") { CaptureDevice.microphone.openSystemSettings() }
                }
            } footer: {
                Text("macOS also controls whether Fern can use these devices at all.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SitePermissionsRow: View {
    let host: String
    let profile: Profile.ID
    private let store = SitePermissionStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: host)
                .lineLimit(1)
            Spacer()
            ForEach(CaptureDevice.allCases, id: \.self) { device in
                Picker(selection: binding(for: device)) {
                    ForEach(SitePermission.allCases, id: \.self) { permission in
                        Text(permission.title).tag(permission)
                    }
                } label: {
                    Image(systemName: device.symbol)
                        .accessibilityLabel(Text(device.title))
                }
                .fixedSize()
            }
            Button {
                store.removeSite(host, profile: profile)
            } label: {
                Label("Remove", systemImage: "minus.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }

    private func binding(for device: CaptureDevice) -> Binding<SitePermission> {
        Binding(
            get: { store.permission(device, host: host, profile: profile) },
            set: { store.set($0, for: device, host: host, profile: profile) }
        )
    }
}
