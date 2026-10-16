import AppKit
import Observation
import SwiftUI

/// A `NSWindow` em que a view está, para os botões da janela desenhados pelo Fern.
@MainActor
@Observable
final class HostWindow {
    @ObservationIgnored weak var window: NSWindow?
    private(set) var isFullScreen = false

    fileprivate func update(from window: NSWindow) {
        self.window = window
        isFullScreen = window.styleMask.contains(.fullScreen)
    }
}

extension EnvironmentValues {
    @Entry var hostWindow: HostWindow? = nil
}

/// Liga a `NSWindow` que o SwiftUI cria ao `HostWindow` e esconde os botões fechar,
/// minimizar e tela cheia do sistema: o Fern desenha os seus (`WindowControls`) na
/// primeira linha da interface, alinhados com os outros botões. Em tela cheia, os do
/// sistema voltam, porque aparecem na barra que desce do topo da tela.
struct WindowConfigurator: NSViewRepresentable {
    let hostWindow: HostWindow

    func makeNSView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.hostWindow = hostWindow
        return view
    }

    func updateNSView(_ view: ConfiguratorView, context: Context) {}

    final class ConfiguratorView: NSView {
        var hostWindow: HostWindow?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }

            let names: [Notification.Name] = [
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.update() }
                }
            }
            update()
        }

        private func update() {
            guard let window else { return }
            hostWindow?.update(from: window)
            let hidesSystemButtons = !window.styleMask.contains(.fullScreen)
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = hidesSystemButtons
            }
        }
    }
}

/// Fechar, minimizar e tela cheia, desenhados pelo Fern. Mostram os símbolos ao passar
/// o mouse e ficam cinza quando a janela não está em foco, como os do sistema.
struct WindowControls: View {
    @Environment(\.hostWindow) private var host
    @Environment(\.controlActiveState) private var activeState
    @State private var isHovering = false

    var body: some View {
        if host?.isFullScreen != true {
            HStack(spacing: 9) {
                control("Close Window", color: Color(light: 0xFF5F57, dark: 0xFF5F57), symbol: "xmark") {
                    host?.window?.performClose(nil)
                }
                control("Minimize", color: Color(light: 0xFEBC2E, dark: 0xFEBC2E), symbol: "minus") {
                    host?.window?.performMiniaturize(nil)
                }
                control(
                    "Full Screen", color: Color(light: 0x28C840, dark: 0x28C840),
                    symbol: "arrow.up.left.and.arrow.down.right"
                ) {
                    // Com Option, amplia a janela em vez de entrar em tela cheia.
                    if NSEvent.modifierFlags.contains(.option) {
                        host?.window?.performZoom(nil)
                    } else {
                        host?.window?.toggleFullScreen(nil)
                    }
                }
            }
            .padding(.leading, 4)
            .onHover { isHovering = $0 }
        }
    }

    private func control(
        _ title: LocalizedStringKey,
        color: Color,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(activeState == .inactive && !isHovering ? Color(light: 0xD5D5D7, dark: 0x4A4B4F) : color)
                .overlay {
                    Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
                }
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.55))
                        .opacity(isHovering ? 1 : 0)
                }
                .frame(width: 14, height: 14)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Área vazia da moldura que arrasta a janela, como uma barra de título. Clique duplo
/// segue a preferência do sistema (ampliar ou minimizar).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

/// Detecta um deslize horizontal com dois dedos no trackpad sobre a área da view. Dispara
/// uma vez por gesto, quando o movimento horizontal passa de um limite.
struct HorizontalSwipeDetector: NSViewRepresentable {
    enum Direction {
        /// Dedos para a esquerda: o conteúdo anda para a esquerda e o próximo aparece.
        case next
        /// Dedos para a direita.
        case previous
    }

    let onSwipe: (Direction) -> Void

    func makeNSView(context: Context) -> DetectorView {
        let view = DetectorView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ view: DetectorView, context: Context) {
        view.onSwipe = onSwipe
    }

    final class DetectorView: NSView {
        var onSwipe: ((Direction) -> Void)?
        private var monitor: Any?
        private var isTracking = false
        private var hasFired = false
        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0
        private static let threshold: CGFloat = 60

        /// Não intercepta cliques: só observa os eventos de rolagem.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        }

        private func handle(_ event: NSEvent) {
            guard event.window === window, event.hasPreciseScrollingDeltas else { return }
            switch event.phase {
            case .began:
                let point = convert(event.locationInWindow, from: nil)
                isTracking = bounds.contains(point)
                hasFired = false
                accumulatedX = 0
                accumulatedY = 0
            case .changed:
                guard isTracking, !hasFired else { return }
                // Converte para a direção dos dedos, com ou sem "rolagem natural".
                let fingerDeltaX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
                accumulatedX += fingerDeltaX
                accumulatedY += abs(event.scrollingDeltaY)
                // Só conta gestos claramente horizontais, para não atrapalhar a rolagem
                // da lista de abas.
                guard abs(accumulatedX) > Self.threshold, abs(accumulatedX) > accumulatedY * 2 else { return }
                hasFired = true
                onSwipe?(accumulatedX < 0 ? .next : .previous)
            case .ended, .cancelled:
                isTracking = false
            default:
                break
            }
        }
    }
}
