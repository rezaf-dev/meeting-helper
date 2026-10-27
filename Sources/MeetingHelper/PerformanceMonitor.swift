import Foundation
import Darwin

@MainActor
final class PerformanceMonitor: ObservableObject {
    @Published var memoryMB: Double = 0
    @Published var cpuPercent: Double = 0
    @Published var thermal = "Normal"
    private var timer: Timer?
    private var previousCPU: Double = 0
    private var previousTime = Date()

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    private func sample() {
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            let now = Date()
            let elapsed = now.timeIntervalSince(previousTime)
            if previousCPU > 0, elapsed > 0 { cpuPercent = max(0, (cpu - previousCPU) / elapsed * 100) }
            previousCPU = cpu
            previousTime = now
        }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS { memoryMB = Double(info.phys_footprint) / 1_048_576 }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Warm"
        case .serious: thermal = "Hot"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unknown"
        }
    }
}
