import Foundation
import Testing

@testable import Fern

@MainActor
struct SitePermissionTests {
    let profile = UUID()

    private func makeStore(_ defaults: UserDefaults = UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!)
        -> SitePermissionStore
    {
        SitePermissionStore(defaults: defaults)
    }

    @Test func asksByDefault() {
        let store = makeStore()
        #expect(store.decision(for: [.camera], host: "meet.example.com", profile: profile) == .ask)
    }

    @Test func allowsOnlyWhenEveryDeviceIsAllowed() {
        let store = makeStore()
        store.set(.allow, for: .camera, host: "meet.example.com", profile: profile)
        #expect(store.decision(for: [.camera], host: "meet.example.com", profile: profile) == .allow)
        #expect(store.decision(for: [.camera, .microphone], host: "meet.example.com", profile: profile) == .ask)

        store.set(.allow, for: .microphone, host: "meet.example.com", profile: profile)
        #expect(store.decision(for: [.camera, .microphone], host: "meet.example.com", profile: profile) == .allow)
    }

    @Test func anyDeniedDeviceDeniesTheRequest() {
        let store = makeStore()
        store.set(.allow, for: .camera, host: "example.com", profile: profile)
        store.set(.deny, for: .microphone, host: "example.com", profile: profile)
        #expect(store.decision(for: [.camera, .microphone], host: "example.com", profile: profile) == .deny)
    }

    @Test func ignoresWWWAndKeepsProfilesApart() {
        let store = makeStore()
        store.set(.allow, for: .camera, host: "www.example.com", profile: profile)
        #expect(store.permission(.camera, host: "example.com", profile: profile) == .allow)
        #expect(store.permission(.camera, host: "example.com", profile: UUID()) == .ask)
    }

    @Test func choosingAskRemovesTheSite() {
        let store = makeStore()
        store.set(.deny, for: .camera, host: "example.com", profile: profile)
        store.set(.ask, for: .camera, host: "example.com", profile: profile)
        #expect(store.sites(for: profile).isEmpty)
    }

    @Test func decisionsAreSaved() {
        let defaults = UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!
        makeStore(defaults).set(.allow, for: .microphone, host: "example.com", profile: profile)
        #expect(makeStore(defaults).permission(.microphone, host: "example.com", profile: profile) == .allow)
    }

    @Test func requestsAnswerOnlyOnce() {
        var answers: [Bool] = []
        let request = PermissionRequest(host: "example.com", devices: [.camera]) { granted, _ in
            answers.append(granted)
        }
        request.resolve(granted: true, remember: false)
        request.resolve(granted: false, remember: false)
        #expect(answers == [true])
    }

    @Test func aNewRequestDeniesThePendingOne() {
        let tab = Tab()
        var first: Bool?
        tab.ask(PermissionRequest(host: "a.example", devices: [.camera]) { granted, _ in first = granted })
        tab.ask(PermissionRequest(host: "b.example", devices: [.microphone]) { _, _ in })
        #expect(first == false)
        #expect(tab.pendingPermission?.host == "b.example")
    }

    @Test func privateWindowsDoNotShareDecisions() {
        let window = BrowserWindow(
            isPrivate: true,
            profiles: ProfileStore(defaults: UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!),
            history: HistoryStore(inMemory: true),
            storage: BrowserStorage(defaults: UserDefaults(suiteName: "FernTests-\(UUID().uuidString)")!),
            restoresSession: false,
            restoreTracker: SessionRestoreTracker()
        )
        #expect(window.sitePermissions !== SitePermissionStore.shared)
    }
}

@MainActor
struct TabAudioTests {
    @Test func startsQuietAndUnmuted() {
        let tab = Tab()
        #expect(!tab.isPlayingAudio)
        #expect(!tab.isAudioMuted)
    }

    @Test func muteTogglesAndSurvivesNavigation() {
        let tab = Tab()
        tab.toggleAudioMuted()
        #expect(tab.isAudioMuted)
        tab.navigationDidStart()
        #expect(tab.isAudioMuted)
        tab.toggleAudioMuted()
        #expect(!tab.isAudioMuted)
    }

    @Test func navigatingAwayClearsTheSound() {
        let tab = Tab()
        tab.navigationDidStart()
        #expect(!tab.isPlayingAudio)
    }
}
