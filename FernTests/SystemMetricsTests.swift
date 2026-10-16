import Foundation
import Testing

@testable import Fern

struct SystemMetricsTests {
    @Test func cpuUsageIsTheBusyShareOfTheElapsedTicks() {
        let before = SystemMetrics.CPUTicks(busy: 100, total: 1_000)
        let after = SystemMetrics.CPUTicks(busy: 150, total: 1_200)
        #expect(SystemMetrics.cpuUsage(from: before, to: after) == 0.25)
    }

    @Test func cpuUsageIsZeroWhenNoTimePassed() {
        let ticks = SystemMetrics.CPUTicks(busy: 100, total: 1_000)
        #expect(SystemMetrics.cpuUsage(from: ticks, to: ticks) == 0)
    }

    @Test func processCPUUsageIsSpreadOverAllCores() {
        let before = SystemMetrics.ProcessUsage(cpuTime: 0, memory: 0)
        // 1 s de CPU em 1 s de relógio, num Mac com 4 núcleos = 25% do Mac.
        let after = SystemMetrics.ProcessUsage(cpuTime: 1_000_000_000, memory: 0)
        #expect(SystemMetrics.processCPUUsage(from: before, to: after, elapsed: .seconds(1), cores: 4) == 0.25)
    }

    @Test func readsTheMac() throws {
        let ticks = try #require(SystemMetrics.cpuTicks())
        #expect(ticks.total >= ticks.busy)

        let memory = try #require(SystemMetrics.memory())
        #expect(memory.used > 0)
        #expect(memory.used <= memory.total)

        let process = try #require(SystemMetrics.processUsage())
        #expect(process.memory > 0)
    }
}
