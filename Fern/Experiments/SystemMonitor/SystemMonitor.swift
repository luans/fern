import Foundation
import Observation

/// Lê as métricas a cada 2 segundos enquanto alguma janela mostra o monitor. Uma
/// instância só para o app: várias janelas não multiplicam o trabalho.
@MainActor
@Observable
final class SystemMonitor {
    static let shared = SystemMonitor()

    static let interval: Duration = .seconds(2)
    /// Quantas leituras de CPU guardar para o gráfico (1 minuto).
    static let historyLength = 30

    /// CPU do Mac, de 0 a 1.
    private(set) var cpu: Double?
    private(set) var cpuHistory: [Double] = []
    private(set) var memory: SystemMetrics.Memory?
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    /// CPU (0 a 1, em relação ao Mac todo) e memória do processo principal do Fern.
    private(set) var appCPU: Double?
    private(set) var appMemory: UInt64?

    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var previousTicks: SystemMetrics.CPUTicks?
    @ObservationIgnored private var previousProcess: SystemMetrics.ProcessUsage?
    @ObservationIgnored private var previousSampleTime: ContinuousClock.Instant?

    /// Cada view que mostra o monitor chama `start` ao aparecer e `stop` ao sumir.
    func start() {
        viewers += 1
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        task?.cancel()
        task = nil
        previousTicks = nil
        previousProcess = nil
        previousSampleTime = nil
    }

    private func sample() {
        let now = ContinuousClock.now

        if let ticks = SystemMetrics.cpuTicks() {
            if let previousTicks {
                let usage = SystemMetrics.cpuUsage(from: previousTicks, to: ticks)
                cpu = usage
                cpuHistory = Array((cpuHistory + [usage]).suffix(Self.historyLength))
            }
            previousTicks = ticks
        }

        memory = SystemMetrics.memory()
        thermalState = ProcessInfo.processInfo.thermalState

        if let process = SystemMetrics.processUsage() {
            appMemory = process.memory
            if let previousProcess, let previousSampleTime {
                appCPU = SystemMetrics.processCPUUsage(
                    from: previousProcess, to: process, elapsed: now - previousSampleTime,
                    cores: ProcessInfo.processInfo.activeProcessorCount)
            }
            previousProcess = process
        }
        previousSampleTime = now
    }
}
