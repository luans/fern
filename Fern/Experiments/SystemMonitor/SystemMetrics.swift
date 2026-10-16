import Darwin
import Foundation

/// Leituras do sistema usadas pelo monitor. Só APIs públicas que funcionam no App
/// Sandbox. Temperatura em graus não entra: o macOS não tem API pública para ela, e o
/// estado térmico (`ProcessInfo.thermalState`) é o que o próprio sistema usa.
enum SystemMetrics {
    /// Contadores de tempo de CPU de todos os núcleos, desde que o Mac ligou.
    struct CPUTicks: Equatable, Sendable {
        var busy: UInt64
        var total: UInt64
    }

    struct Memory: Equatable, Sendable {
        /// Equivalente a "Memória Usada" do Monitor de Atividade.
        var used: UInt64
        var total: UInt64
        var pressure: MemoryPressure
    }

    enum MemoryPressure: Sendable {
        case normal, warning, critical, unknown
    }

    /// Uso do processo principal do Fern. As páginas rodam em processos do WebKit que
    /// não entram aqui (ver `SystemMonitor`).
    struct ProcessUsage: Equatable, Sendable {
        /// Tempo de CPU acumulado, em nanossegundos.
        var cpuTime: UInt64
        /// Memória do processo como o Monitor de Atividade conta ("footprint").
        var memory: UInt64
    }

    // MARK: - CPU

    static func cpuTicks() -> CPUTicks? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(load.cpu_ticks.0)
        let system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2)
        let nice = UInt64(load.cpu_ticks.3)
        return CPUTicks(busy: user + system + nice, total: user + system + idle + nice)
    }

    /// Fração de 0 a 1 do tempo em que a CPU ficou ocupada entre duas leituras.
    static func cpuUsage(from previous: CPUTicks, to current: CPUTicks) -> Double {
        guard current.total > previous.total, current.busy >= previous.busy else { return 0 }
        let busy = Double(current.busy - previous.busy)
        let total = Double(current.total - previous.total)
        return min(max(busy / total, 0), 1)
    }

    // MARK: - Memória

    static func memory() -> Memory? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(getpagesize())
        // Memória de apps (sem a que pode ser descartada) + fixa + comprimida.
        let appPages =
            UInt64(stats.internal_page_count)
            - min(
                UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return Memory(
            used: usedPages * pageSize,
            total: ProcessInfo.processInfo.physicalMemory,
            pressure: memoryPressure()
        )
    }

    private static func memoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }

    // MARK: - Processo

    static func processUsage(pid: pid_t = getpid()) -> ProcessUsage? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        // Os tempos vêm em unidades do relógio da máquina; o timebase converte para ns.
        let ticks = info.ri_user_time + info.ri_system_time
        return ProcessUsage(
            cpuTime: ticks * UInt64(timebase.numer) / UInt64(timebase.denom),
            memory: info.ri_phys_footprint
        )
    }

    /// Fração de 0 a 1 da CPU total do Mac usada pelo processo entre duas leituras.
    static func processCPUUsage(
        from previous: ProcessUsage, to current: ProcessUsage, elapsed: Duration, cores: Int
    ) -> Double {
        let elapsedNanoseconds =
            Double(elapsed.components.seconds) * 1e9
            + Double(elapsed.components.attoseconds) / 1e9
        guard elapsedNanoseconds > 0, cores > 0, current.cpuTime >= previous.cpuTime else { return 0 }
        let used = Double(current.cpuTime - previous.cpuTime)
        return min(max(used / (elapsedNanoseconds * Double(cores)), 0), 1)
    }

    // MARK: - Recursos do sistema

    private static let host = mach_host_self()

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
}
