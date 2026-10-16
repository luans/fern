import SwiftUI

/// Linha compacta no rodapé da barra lateral: CPU, memória e um ponto com o estado
/// térmico. Clique para ver os detalhes.
struct SystemMonitorIndicator: View {
    private let monitor = SystemMonitor.shared
    @State private var isShowingDetails = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isShowingDetails.toggle()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(monitor.thermalState.color)
                    .frame(width: 7, height: 7)
                metric("CPU", value: monitor.cpu.map(percent) ?? "–")
                metric("RAM", value: monitor.memory.map { percent(Double($0.used) / Double($0.total)) } ?? "–")
                Spacer(minLength: 0)
                Sparkline(values: monitor.cpuHistory)
                    .frame(width: 44, height: 14)
            }
            .font(.system(size: 11).monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                (isHovering ? Theme.surface.opacity(0.6) : Theme.groupedCard),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("System monitor")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System monitor")
        .accessibilityValue(accessibilitySummary)
        .popover(isPresented: $isShowingDetails, arrowEdge: .top) {
            SystemMonitorDetails()
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func metric(_ label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
        }
    }

    private var accessibilitySummary: Text {
        Text(
            "CPU \(monitor.cpu.map(percent) ?? "–"), memory \(monitor.memory.map { percent(Double($0.used) / Double($0.total)) } ?? "–"), \(String(localized: monitor.thermalState.title))"
        )
    }
}

/// Balão com os detalhes do Mac e do Fern.
private struct SystemMonitorDetails: View {
    private let monitor = SystemMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Mac")
                .font(.headline)

            row("CPU") {
                Text(verbatim: monitor.cpu.map(percent) ?? "–")
            }
            Sparkline(values: monitor.cpuHistory)
                .frame(height: 28)

            row("Memory") {
                if let memory = monitor.memory {
                    Text(verbatim: "\(bytes(memory.used)) / \(bytes(memory.total))")
                } else {
                    Text(verbatim: "–")
                }
            }
            row("Memory pressure") {
                Text(monitor.memory?.pressure.title ?? "–")
                    .foregroundStyle(monitor.memory?.pressure.color ?? .secondary)
            }
            row("Thermal state") {
                HStack(spacing: 5) {
                    Circle()
                        .fill(monitor.thermalState.color)
                        .frame(width: 7, height: 7)
                    Text(monitor.thermalState.title)
                }
            }
            Text(monitor.thermalState.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text(verbatim: "Fern")
                .font(.headline)
            row("CPU") {
                Text(verbatim: monitor.appCPU.map(percent) ?? "–")
            }
            row("Memory") {
                Text(verbatim: monitor.appMemory.map(bytes) ?? "–")
            }
            Text(
                "Only the app's main process. The pages run in WebKit processes that macOS doesn't let a sandboxed app measure."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout.monospacedDigit())
        .padding(16)
        .frame(width: 280)
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            value()
        }
    }
}

/// Gráfico de linha mínimo dos últimos valores (0 a 1).
private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let points = values.suffix(SystemMonitor.historyLength)
            let step = geometry.size.width / CGFloat(max(SystemMonitor.historyLength - 1, 1))
            let start = geometry.size.width - step * CGFloat(max(points.count - 1, 0))
            Path { path in
                for (index, value) in points.enumerated() {
                    let point = CGPoint(
                        x: start + step * CGFloat(index),
                        y: geometry.size.height * (1 - CGFloat(value)))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private func percent(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(0)))
}

private func bytes(_ value: UInt64) -> String {
    Int64(value).formatted(.byteCount(style: .memory))
}

extension ProcessInfo.ThermalState {
    fileprivate var color: Color {
        switch self {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        @unknown default: .gray
        }
    }

    fileprivate var title: LocalizedStringResource {
        switch self {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    fileprivate var explanation: LocalizedStringKey {
        switch self {
        case .nominal: "The Mac is running at full speed."
        case .fair: "The Mac is a little warm. Fans may speed up."
        case .serious: "The Mac is hot and may slow down to cool off."
        case .critical: "The Mac is very hot and is slowing down to cool off."
        @unknown default: "macOS doesn't report the temperature in degrees; this is its thermal state."
        }
    }
}

extension SystemMetrics.MemoryPressure {
    fileprivate var title: LocalizedStringKey {
        switch self {
        case .normal: "Normal"
        case .warning: "High"
        case .critical: "Critical"
        case .unknown: "Unknown"
        }
    }

    fileprivate var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }
}
