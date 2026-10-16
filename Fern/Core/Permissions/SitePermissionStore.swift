import Foundation
import Observation

/// Dispositivos que uma página pode pedir para usar.
enum CaptureDevice: String, Codable, CaseIterable, Sendable {
    case camera, microphone
}

/// O que o Fern faz quando um site pede um dispositivo.
enum SitePermission: String, Codable, CaseIterable, Sendable {
    /// Pergunta a cada vez (padrão).
    case ask
    case allow
    case deny
}

/// Decisões de câmera e microfone por site e por perfil. Janelas privadas usam uma
/// instância só em memória, que some com a janela.
@MainActor
@Observable
final class SitePermissionStore {
    static let shared = SitePermissionStore(defaults: .standard)

    private static let storageKey = "sitePermissions"

    /// Perfil → site (sem "www.") → dispositivo → decisão.
    private(set) var entries: [Profile.ID: [String: [CaptureDevice: SitePermission]]] = [:]

    @ObservationIgnored private let defaults: UserDefaults?

    /// - Parameter defaults: onde salvar. `nil` guarda só na memória (janelas privadas).
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        entries = load()
    }

    static func inMemory() -> SitePermissionStore {
        SitePermissionStore(defaults: nil)
    }

    // MARK: - Consultar

    func permission(_ device: CaptureDevice, host: String, profile: Profile.ID) -> SitePermission {
        guard let host = ContentBlocker.normalizedHost(host) else { return .ask }
        return entries[profile]?[host]?[device] ?? .ask
    }

    /// Decisão para um pedido com um ou mais dispositivos: nega se algum está negado,
    /// permite se todos estão permitidos, senão pergunta.
    func decision(for devices: [CaptureDevice], host: String, profile: Profile.ID) -> SitePermission {
        let permissions = devices.map { permission($0, host: host, profile: profile) }
        if permissions.contains(.deny) { return .deny }
        if !permissions.isEmpty, permissions.allSatisfy({ $0 == .allow }) { return .allow }
        return .ask
    }

    /// Sites com alguma decisão salva, em ordem alfabética.
    func sites(for profile: Profile.ID) -> [(host: String, permissions: [CaptureDevice: SitePermission])] {
        (entries[profile] ?? [:]).sorted { $0.key < $1.key }.map { (host: $0.key, permissions: $0.value) }
    }

    // MARK: - Alterar

    func set(_ permission: SitePermission, for device: CaptureDevice, host: String, profile: Profile.ID) {
        guard let host = ContentBlocker.normalizedHost(host) else { return }
        var sites = entries[profile] ?? [:]
        var devices = sites[host] ?? [:]
        devices[device] = permission == .ask ? nil : permission
        sites[host] = devices.isEmpty ? nil : devices
        entries[profile] = sites.isEmpty ? nil : sites
        save()
    }

    func removeSite(_ host: String, profile: Profile.ID) {
        entries[profile]?[host] = nil
        if entries[profile]?.isEmpty == true { entries[profile] = nil }
        save()
    }

    func removeAll(profile: Profile.ID) {
        entries[profile] = nil
        save()
    }

    // MARK: - Salvar

    private typealias Stored = [String: [String: [String: String]]]

    private func save() {
        guard let defaults else { return }
        let stored: Stored = Dictionary(
            uniqueKeysWithValues: entries.map { profile, sites in
                (
                    profile.uuidString,
                    sites.mapValues { devices in
                        Dictionary(uniqueKeysWithValues: devices.map { ($0.key.rawValue, $0.value.rawValue) })
                    }
                )
            })
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.storageKey)
    }

    private func load() -> [Profile.ID: [String: [CaptureDevice: SitePermission]]] {
        guard let data = defaults?.data(forKey: Self.storageKey),
            let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return [:] }
        var result: [Profile.ID: [String: [CaptureDevice: SitePermission]]] = [:]
        for (profileString, sites) in stored {
            guard let profile = UUID(uuidString: profileString) else { continue }
            result[profile] = sites.mapValues { devices in
                var decoded: [CaptureDevice: SitePermission] = [:]
                for (device, permission) in devices {
                    if let device = CaptureDevice(rawValue: device),
                        let permission = SitePermission(rawValue: permission)
                    {
                        decoded[device] = permission
                    }
                }
                return decoded
            }
        }
        return result
    }
}

/// Um pedido de câmera ou microfone esperando a resposta do usuário na aba.
@MainActor
final class PermissionRequest: Identifiable {
    let id = UUID()
    let host: String
    let devices: [CaptureDevice]
    private var completion: ((_ granted: Bool, _ remember: Bool) -> Void)?

    init(host: String, devices: [CaptureDevice], completion: @escaping (_ granted: Bool, _ remember: Bool) -> Void) {
        self.host = host
        self.devices = devices
        self.completion = completion
    }

    /// Responde uma vez só; chamadas seguintes são ignoradas.
    func resolve(granted: Bool, remember: Bool) {
        completion?(granted, remember)
        completion = nil
    }
}
