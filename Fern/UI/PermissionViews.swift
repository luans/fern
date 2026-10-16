import AVFoundation
import SwiftUI

extension CaptureDevice {
    var symbol: String {
        switch self {
        case .camera: "video.fill"
        case .microphone: "mic.fill"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        }
    }

    /// Se o macOS bloqueou o Fern de usar o dispositivo (Ajustes do Sistema).
    var isBlockedBySystem: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: self == .camera ? .video : .audio)
        return status == .denied || status == .restricted
    }

    /// Abre Ajustes do Sistema na lista de apps com acesso a este dispositivo.
    func openSystemSettings() {
        let pane = self == .camera ? "Privacy_Camera" : "Privacy_Microphone"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension SitePermission {
    var title: LocalizedStringResource {
        switch self {
        case .ask: "Ask"
        case .allow: "Allow"
        case .deny: "Deny"
        }
    }
}

/// Pedido de câmera ou microfone, no topo da página que pediu.
struct PermissionBanner: View {
    let tab: Tab
    let request: PermissionRequest

    @State private var remember = true

    private var blockedDevices: [CaptureDevice] {
        request.devices.filter(\.isBlockedBySystem)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(request.devices, id: \.self) { device in
                        Image(systemName: device.symbol)
                    }
                }
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let device = blockedDevices.first {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("macOS is blocking Fern from using this. Allow it in System Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings") { device.openSystemSettings() }
                        .controlSize(.small)
                }
            }

            HStack {
                Toggle("Remember for this site", isOn: $remember)
                    .toggleStyle(.checkbox)
                    .disabled(tab.browserWindow?.isPrivate == true)
                Spacer()
                Button("Don't Allow") { tab.answerPermission(granted: false, remember: remember) }
                Button("Allow") { tab.answerPermission(granted: true, remember: remember) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(maxWidth: 460)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline))
        .padding(.top, 14)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            // Numa janela privada, nada é lembrado.
            if tab.browserWindow?.isPrivate == true { remember = false }
        }
    }

    private var message: String {
        let devices = Set(request.devices)
        if devices == [.camera, .microphone] {
            return String(localized: "\(request.host) wants to use your camera and microphone.")
        } else if devices == [.camera] {
            return String(localized: "\(request.host) wants to use your camera.")
        } else {
            return String(localized: "\(request.host) wants to use your microphone.")
        }
    }
}

/// Ícones de câmera, microfone e som numa aba. Clicar pausa (ou retoma) o dispositivo,
/// ou silencia (ou devolve o som da) aba.
struct TabMediaIndicators: View {
    let tab: Tab

    var body: some View {
        HStack(spacing: 2) {
            if tab.cameraCaptureState != .none {
                indicator(
                    symbol: tab.cameraCaptureState == .muted ? "video.slash.fill" : "video.fill",
                    isLive: tab.cameraCaptureState == .active,
                    help: tab.cameraCaptureState == .muted ? "Turn Camera On" : "Pause Camera"
                ) { tab.toggleCameraMuted() }
            }
            if tab.microphoneCaptureState != .none {
                indicator(
                    symbol: tab.microphoneCaptureState == .muted ? "mic.slash.fill" : "mic.fill",
                    isLive: tab.microphoneCaptureState == .active,
                    help: tab.microphoneCaptureState == .muted ? "Turn Microphone On" : "Mute Microphone"
                ) { tab.toggleMicrophoneMuted() }
            }
            if tab.isAudioMuted {
                indicator(symbol: "speaker.slash.fill", isLive: false, help: "Unmute Tab") {
                    tab.toggleAudioMuted()
                }
            } else if tab.isPlayingAudio {
                indicator(symbol: "speaker.wave.2.fill", isLive: false, help: "Mute Tab") {
                    tab.toggleAudioMuted()
                }
            }
        }
    }

    private func indicator(
        symbol: String, isLive: Bool, help: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isLive ? Color.red : Color.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
