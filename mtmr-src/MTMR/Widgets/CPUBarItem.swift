//
//  CPUBarItem.swift
//  MTMR
//
//  Created by bobrosoft on 17/08/2021.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation
import IOKit
import Darwin

class CPUBarItem: CustomButtonTouchBarItem {
    private let refreshInterval: TimeInterval
    private var refreshQueue: DispatchQueue? = DispatchQueue(label: "mtmr.cpu")
    private let defaultSingleTapScript: NSAppleScript! = "activate application \"Activity Monitor\"\rtell application \"System Events\"\r\ttell process \"Activity Monitor\"\r\t\ttell radio button \"CPU\" of radio group 1 of group 2 of toolbar 1 of window 1 to perform action \"AXPress\"\r\tend tell\rend tell".appleScript

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: TimeInterval) {
        self.refreshInterval = refreshInterval
        super.init(identifier: identifier, title: "CPU")
                
        // Set default image
        if self.image == nil {
            self.image = StudioControlStyle.image("cpu",fallback:#imageLiteral(resourceName: "cpu").resize(maxSize:NSSize(width:20,height:20)))
        }
        
        // Set default action
        if actions.filter({ $0.trigger == .singleTap }).isEmpty {
            actions.append(ItemAction(
                trigger: .singleTap,
                defaultTapAction
            ))
        }
        
        refreshAndSchedule()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func refreshAndSchedule() {
        DispatchQueue.main.async {
            // Get CPU load
            let usage = 100 - CPU.systemUsage().idle
            let label = SystemMetrics.cpuUsageLabel(usage)
            guard label != "—" else {
                return
            }
            
            // Choose color based on CPU load
            var color: NSColor? = nil
            var bgColor: NSColor? = nil
            if usage > 70 {
                color = .black
                bgColor = .yellow
            } else if usage > 30 {
                color = .yellow
            }
            
            // Update layout
            let attrTitle = NSMutableAttributedString(attributedString: label.defaultTouchbarAttributedString)
            if let color = color {
                attrTitle.addAttributes([.foregroundColor: color], range: NSRange(location: 0, length: attrTitle.length))
            }
            self.attributedTitle = attrTitle
            self.backgroundColor = bgColor
            self.view.toolTip = "CPU usage: \(label)."
            self.view.setAccessibilityLabel("CPU usage")
        }
        
        refreshQueue?.asyncAfter(deadline: .now() + refreshInterval) { [weak self] in
            self?.refreshAndSchedule()
        }
    }

    func defaultTapAction() {
        refreshQueue?.async { [weak self] in
            self?.defaultSingleTapScript.executeAndReturnError(nil)
        }
    }
    
    deinit {
        refreshQueue = nil
    }
}

/// A cached system-wide sample shared by all metrics controls. Calls are
/// serialized and coalesced so multiple widgets never enumerate sensors every
/// refresh tick.
struct SystemMetricsSnapshot {
    let cpuUtilization: Double?
    let ramUsedBytes: UInt64?
    let ramTotalBytes: UInt64
    let gpuUtilization: Double?
    let cpuTemperatureCelsius: Double?
}

enum SystemMetrics {
    enum Monitor: Hashable { case cpu, ram, gpu, cpuTemperature }
    static let didUpdate = Notification.Name("TouchBarStudio.SystemMetricsDidUpdate")
    private static let queue = DispatchQueue(label: "mtmr.system-metrics", qos: .utility)
    // mach_host_self() returns a send right; keep one for this sampler's
    // lifetime instead of requesting another right on every RAM refresh.
    private static let hostPort = mach_host_self()
    private static var timer: DispatchSourceTimer?
    private static var monitorCounts: [Monitor: Int] = [:]
    private static var cpuTemperatureReader: AppleSMCTemperatureReader?
    private static var previousCPUTicks: [UInt32]?
    private static var cached = SystemMetricsSnapshot(cpuUtilization: nil, ramUsedBytes: nil, ramTotalBytes: ProcessInfo.processInfo.physicalMemory, gpuUtilization: nil, cpuTemperatureCelsius: nil)

    static func startMonitoring(_ monitor: Monitor) {
        queue.async {
            monitorCounts[monitor, default: 0] += 1
            if monitor == .cpu, monitorCounts[monitor] == 1 { previousCPUTicks = nil }
            if monitor == .cpuTemperature, cpuTemperatureReader == nil {
                cpuTemperatureReader = AppleSMCTemperatureReader()
            }
            if timer == nil {
                let source = DispatchSource.makeTimerSource(queue: queue)
                source.schedule(deadline: .now(), repeating: 2)
                source.setEventHandler {
                    cached = readSnapshot(includeCPU: (monitorCounts[.cpu] ?? 0) > 0, includeRAM: (monitorCounts[.ram] ?? 0) > 0, includeGPU: (monitorCounts[.gpu] ?? 0) > 0, includeCPUTemperature: (monitorCounts[.cpuTemperature] ?? 0) > 0)
                    let sample = cached
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: didUpdate, object: sample)
                    }
                }
                timer = source
                source.resume()
            }
        }
    }

    static func stopMonitoring(_ monitor: Monitor) {
        queue.async {
            monitorCounts[monitor] = max(0, (monitorCounts[monitor] ?? 0) - 1)
            if monitorCounts[monitor] == 0 { monitorCounts.removeValue(forKey: monitor) }
            if monitor == .cpuTemperature, monitorCounts[monitor] == nil {
                cpuTemperatureReader?.close()
            }
            guard monitorCounts.isEmpty else { return }
            timer?.cancel()
            timer = nil
        }
    }

    static func snapshot() -> SystemMetricsSnapshot { queue.sync { cached } }
    static var cpuTemperatureReadTiming: (inventoryMilliseconds: Double, sampleMilliseconds: Double)? {
        queue.sync {
            guard let reader = cpuTemperatureReader,
                  let inventory = reader.inventoryMilliseconds,
                  let sample = reader.lastSampleMilliseconds else { return nil }
            return (inventory, sample)
        }
    }
    static var monitorSubscriberCount: Int { queue.sync { monitorCounts.values.reduce(0, +) } }
    static var isSampling: Bool { queue.sync { timer != nil } }
    static func monitorSubscriberCount(for monitor: Monitor) -> Int { queue.sync { monitorCounts[monitor] ?? 0 } }

    static func ramPercent(used: UInt64?, total: UInt64) -> Int? {
        guard let used, total > 0 else { return nil }
        return Int(min(100, max(0, (Double(used) / Double(total) * 100).rounded())))
    }

    static func ramUsedBytes(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressedPages: UInt64, pageSize: UInt64) -> UInt64? {
        guard purgeablePages <= internalPages, pageSize > 0 else { return nil }
        let resident = (internalPages - purgeablePages).addingReportingOverflow(wiredPages)
        guard !resident.overflow else { return nil }
        let pages = resident.partialValue.addingReportingOverflow(compressedPages)
        guard !pages.overflow else { return nil }
        let bytes = pages.partialValue.multipliedReportingOverflow(by: pageSize)
        return bytes.overflow ? nil : bytes.partialValue
    }

    static func ramDetail(used: UInt64?, total: UInt64) -> String {
        guard let used, total > 0 else { return "RAM usage unavailable" }
        return String(format: "RAM used: %@ / %@ physical memory (non-purgeable internal + wired + compressed pages; not Activity Monitor-equivalent)", ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .memory), ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .memory))
    }

    static func gpuPercent(_ value: Double?) -> Int? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return Int(value.rounded())
    }

    static func cpuUsageLabel(_ value: Double?) -> String {
        guard let value, value.isFinite, (0...100).contains(value) else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    static let unsupportedBoardLabel = "Board —"

    static func cpuTemperatureLabel(_ value: Double?) -> String {
        guard let value, value.isFinite, (0.1...130).contains(value) else { return "CPU —" }
        return "CPU \(Int(value.rounded()))°C"
    }

    private static func readSnapshot(includeCPU: Bool, includeRAM: Bool, includeGPU: Bool, includeCPUTemperature: Bool) -> SystemMetricsSnapshot {
        let total = ProcessInfo.processInfo.physicalMemory
        let used: UInt64?
        if includeRAM {
            var vm = vm_statistics64()
            var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &vm) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
                }
            }
            if result == KERN_SUCCESS {
                used = ramUsedBytes(internalPages: UInt64(vm.internal_page_count), purgeablePages: UInt64(vm.purgeable_count), wiredPages: UInt64(vm.wire_count), compressedPages: UInt64(vm.compressor_page_count), pageSize: UInt64(vm_page_size))
            } else {
                used = nil
            }
        } else {
            used = nil
        }
        return SystemMetricsSnapshot(cpuUtilization: includeCPU ? readCPUUtilization() : nil, ramUsedBytes: used, ramTotalBytes: total, gpuUtilization: includeGPU ? readGPUUtilization() : nil, cpuTemperatureCelsius: includeCPUTemperature ? cpuTemperatureReader?.hottestReadingCelsius() : nil)
    }

    private static func readCPUUtilization() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { previousCPUTicks = nil; return nil }
        let ticks: [UInt32] = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previousCPUTicks = ticks }
        guard let previousCPUTicks,
              let value = cpuPercent(previous: previousCPUTicks, current: ticks) else { return nil }
        return value
    }

    static func cpuPercent(previous: [UInt32], current: [UInt32]) -> Double? {
        guard previous.count == 4, current.count == 4 else { return nil }
        let deltas = zip(previous, current).map { $1 &- $0 }
        let total = deltas.reduce(UInt64(0)) { $0 + UInt64($1) }
        guard total > 0 else { return nil }
        let idle = UInt64(deltas[2])
        return Double(total - idle) / Double(total) * 100
    }

    /// IOAccelerator exposes a system-wide device utilization counter on this
    /// Mac. Use the busiest device when more than one is present; never sum
    /// percentages across devices.
    private static func readGPUUtilization() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var busiest: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let currentService = service
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(currentService, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let values = properties?.takeRetainedValue() as? [String: Any],
               let statistics = values["PerformanceStatistics"] as? [String: Any],
               let number = statistics["Device Utilization %"] as? NSNumber {
                let value = number.doubleValue
                if value.isFinite, (0...100).contains(value) { busiest = max(busiest ?? value, value) }
            }
            IOObjectRelease(currentService)
            service = IOIteratorNext(iterator)
        }
        return busiest
    }

    /// Read only model-exposed Apple Silicon CPU sensor keys. `Tp` and `Te`
    /// prefixes are the SMC CPU performance/efficiency sensor families; only
    /// four-byte IEEE float entries are accepted. The hottest valid reading is
    /// displayed, avoiding a guess at the identities of opaque individual keys.
    private final class AppleSMCTemperatureReader {
        private static let structureSize = 80
        private static let resultOffset = 40
        private static let commandOffset = 42
        private static let data32Offset = 44
        private static let bytesOffset = 48
        private static let dataSizeOffset = 28
        private static let dataTypeOffset = 32

        private var connection: io_connect_t = 0
        private var cpuSensorKeys: [(code: UInt32, size: UInt32)] = []
        private var didDiscoverKeys = false
        private(set) var inventoryMilliseconds: Double?
        private(set) var lastSampleMilliseconds: Double?

        init() {}

        private func openIfNeeded() -> Bool {
            if connection != 0 { return true }
            guard let matching = IOServiceMatching("AppleSMC") else { return false }
            let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
            guard service != 0 else { return false }
            defer { IOObjectRelease(service) }
            guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
                connection = 0
                return false
            }
            if !didDiscoverKeys {
                let start = DispatchTime.now().uptimeNanoseconds
                cpuSensorKeys = discoverCPUSensorKeys()
                inventoryMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                didDiscoverKeys = true
            }
            return true
        }

        func close() {
            guard connection != 0 else { return }
            IOServiceClose(connection)
            connection = 0
        }

        deinit { close() }

        func hottestReadingCelsius() -> Double? {
            guard openIfNeeded() else { return nil }
            let start = DispatchTime.now().uptimeNanoseconds
            let hottest = cpuSensorKeys.compactMap { readFloat(key: $0.code, size: $0.size) }
                .filter { $0.isFinite && (0.1...130).contains($0) }
                .max()
            lastSampleMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            return hottest
        }

        private func discoverCPUSensorKeys() -> [(code: UInt32, size: UInt32)] {
            guard let countBytes = readData(for: Self.fourCC("#KEY"), expectedSize: 4) else { return [] }
            let count = Self.readBigEndianUInt32(countBytes, offset: 0)
            guard count > 0, count <= 4_096 else { return [] }

            var keys: [(code: UInt32, size: UInt32)] = []
            for index in 0..<count {
                guard let keyOutput = call(command: 8, key: 0, data32: index),
                      keyOutput[Self.resultOffset] == 0 else { continue }
                let code = Self.readNativeUInt32(keyOutput, offset: 0)
                let name = Self.fourCCString(code)
                guard name.hasPrefix("Tp") || name.hasPrefix("Te") else { continue }
                guard let info = call(command: 9, key: code, data32: 0),
                      info[Self.resultOffset] == 0,
                      Self.readNativeUInt32(info, offset: Self.dataTypeOffset) == Self.fourCC("flt ") else { continue }
                let size = Self.readNativeUInt32(info, offset: Self.dataSizeOffset)
                if size == 4 { keys.append((code, size)) }
            }
            return keys
        }

        private func readFloat(key: UInt32, size: UInt32) -> Double? {
            // Sensor metadata was validated during the one-time key inventory;
            // only request its four-byte value on each two-second sample.
            guard size == 4,
                  let output = call(command: 5, key: key, data32: 0, dataSize: size),
                  output[Self.resultOffset] == 0 else { return nil }
            let bitPattern = Self.readNativeUInt32(output, offset: Self.bytesOffset)
            return Double(Float(bitPattern: bitPattern))
        }

        private func readData(for key: UInt32, expectedSize: UInt32) -> [UInt8]? {
            guard let info = call(command: 9, key: key, data32: 0),
                  info[Self.resultOffset] == 0 else { return nil }
            let size = Self.readNativeUInt32(info, offset: Self.dataSizeOffset)
            guard size == expectedSize, let output = call(command: 5, key: key, data32: 0, dataSize: size),
                  output[Self.resultOffset] == 0 else { return nil }
            return Array(output[Self.bytesOffset..<(Self.bytesOffset + Int(size))])
        }

        private func call(command: UInt8, key: UInt32, data32: UInt32, dataSize: UInt32 = 0) -> [UInt8]? {
            guard connection != 0 else { return nil }
            var input = [UInt8](repeating: 0, count: Self.structureSize)
            var output = [UInt8](repeating: 0, count: Self.structureSize)
            Self.writeNativeUInt32(key, to: &input, offset: 0)
            Self.writeNativeUInt32(dataSize, to: &input, offset: Self.dataSizeOffset)
            input[Self.commandOffset] = command
            Self.writeNativeUInt32(data32, to: &input, offset: Self.data32Offset)
            var outputSize = Self.structureSize
            let result = input.withUnsafeBytes { inputBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    IOConnectCallStructMethod(connection, 2, inputBuffer.baseAddress!, Self.structureSize, outputBuffer.baseAddress!, &outputSize)
                }
            }
            guard result == KERN_SUCCESS, outputSize >= Self.structureSize else { return nil }
            return output
        }

        private static func fourCC(_ string: String) -> UInt32 {
            string.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
        }

        private static func fourCCString(_ code: UInt32) -> String {
            String(bytes: [(code >> 24) & 0xff, (code >> 16) & 0xff, (code >> 8) & 0xff, code & 0xff].map(UInt8.init), encoding: .ascii) ?? ""
        }

        private static func readNativeUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }

        private static func readBigEndianUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
            UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
        }

        private static func writeNativeUInt32(_ value: UInt32, to bytes: inout [UInt8], offset: Int) {
            bytes[offset] = UInt8(truncatingIfNeeded: value)
            bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
            bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
            bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
        }
    }
}

class SystemMetricBarItem: CustomButtonTouchBarItem {
    private var observer: NSObjectProtocol?
    private let monitor: SystemMetrics.Monitor

    init(identifier: NSTouchBarItem.Identifier, title: String, symbol: String, monitor: SystemMetrics.Monitor, accessibilityLabel: String) {
        self.monitor = monitor
        super.init(identifier: identifier, title: title)
        image = StudioControlStyle.image(symbol)
        view.setAccessibilityLabel(accessibilityLabel)
        observer = NotificationCenter.default.addObserver(forName: SystemMetrics.didUpdate, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        SystemMetrics.startMonitoring(monitor)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func display(_ title: String, detail: String) {
        self.title = title
        view.toolTip = detail
    }
    func refresh() {}
    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        SystemMetrics.stopMonitoring(monitor)
    }
}

final class RAMUsageBarItem: SystemMetricBarItem {
    init(identifier: NSTouchBarItem.Identifier) { super.init(identifier: identifier, title: "—", symbol: "ramUsage", monitor: .ram, accessibilityLabel: "RAM usage") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func refresh() {
        let sample = SystemMetrics.snapshot()
        let percent = SystemMetrics.ramPercent(used: sample.ramUsedBytes, total: sample.ramTotalBytes)
        display(percent.map { "\($0)%" } ?? "—", detail: "RAM usage: " + SystemMetrics.ramDetail(used: sample.ramUsedBytes, total: sample.ramTotalBytes))
    }
}

final class GPUUsageBarItem: SystemMetricBarItem {
    init(identifier: NSTouchBarItem.Identifier) { super.init(identifier: identifier, title: "—", symbol: "gpuUsage", monitor: .gpu, accessibilityLabel: "GPU usage") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func refresh() {
        let value = SystemMetrics.gpuPercent(SystemMetrics.snapshot().gpuUtilization)
        display(value.map { "\($0)%" } ?? "—", detail: value.map { "System-wide GPU device utilization: \($0)%. Multiple GPUs show the busiest device." } ?? "GPU utilization unavailable: this Mac did not expose an IOAccelerator device utilization counter.")
    }
}

final class CPUTemperatureBarItem: SystemMetricBarItem {
    init(identifier: NSTouchBarItem.Identifier) { super.init(identifier: identifier, title: "—", symbol: "cpuTemperature", monitor: .cpuTemperature, accessibilityLabel: "CPU temperature") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func refresh() {
        let value = SystemMetrics.snapshot().cpuTemperatureCelsius
        display(value.map { "\(Int($0.rounded()))°C" } ?? "—", detail: value.map { "Hottest available AppleSMC CPU sensor reading: \(Int($0.rounded()))°C (Tp/Te temperature keys)." } ?? "CPU temperature unavailable: no readable AppleSMC Tp/Te float sensors were exposed.")
    }
}

final class SystemMonitorBarItem: CustomButtonTouchBarItem {
    private let metrics: [String]
    private let monitors: [SystemMetrics.Monitor]
    private var observer: NSObjectProtocol?

    init(identifier: NSTouchBarItem.Identifier, metrics requested: [String]) {
        let order = ["cpu", "gpu", "memory", "temperature"]
        metrics = order.filter { requested.contains($0) }
        monitors = metrics.compactMap { metric in
            switch metric {
            case "cpu": return .cpu
            case "gpu": return .gpu
            case "memory": return .ram
            case "temperature": return .cpuTemperature
            default: return nil
            }
        }
        super.init(identifier: identifier, title: "")
        image = StudioControlStyle.image("systemMonitor", fallback:NSImage(systemSymbolName:"speedometer", accessibilityDescription:nil))
        view.setAccessibilityLabel("System monitor")
        if !monitors.isEmpty {
            observer = NotificationCenter.default.addObserver(forName:SystemMetrics.didUpdate, object:nil, queue:.main) { [weak self] _ in self?.refresh() }
            monitors.forEach(SystemMetrics.startMonitoring)
            refresh()
        } else {
            view.toolTip = "System monitor. No readings selected."
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func refresh() {
        let sample = SystemMetrics.snapshot()
        var values: [String] = []
        var details: [String] = []
        for metric in metrics {
            switch metric {
            case "cpu":
                let value = SystemMetrics.cpuUsageLabel(sample.cpuUtilization)
                values.append(value)
                details.append("CPU usage: \(value)")
            case "gpu":
                let value = SystemMetrics.gpuPercent(sample.gpuUtilization).map { "\($0)%" } ?? "—"
                values.append(value)
                details.append(value == "—" ? "GPU usage unavailable: no IOAccelerator utilization counter was exposed." : "GPU usage: \(value). Multiple GPUs show the busiest device.")
            case "memory":
                let value = SystemMetrics.ramPercent(used:sample.ramUsedBytes, total:sample.ramTotalBytes).map { "\($0)%" } ?? "—"
                values.append(value)
                details.append("Memory usage: \(value). " + SystemMetrics.ramDetail(used:sample.ramUsedBytes,total:sample.ramTotalBytes))
            case "temperature":
                let value = sample.cpuTemperatureCelsius.map { "\(Int($0.rounded()))°C" } ?? "—"
                values.append(value)
                details.append(value == "—" ? "CPU temperature unavailable: no readable AppleSMC Tp/Te float sensors were exposed." : "CPU temperature: \(value), hottest available AppleSMC CPU sensor.")
            default: break
            }
        }
        title = values.joined(separator:" · ")
        view.toolTip = details.isEmpty ? "System monitor. No readings selected." : details.joined(separator:"\n")
        view.setAccessibilityLabel(details.isEmpty ? "System monitor. No readings selected." : details.joined(separator:", "))
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        monitors.forEach(SystemMetrics.stopMonitoring)
    }
}

final class BoardTemperatureBarItem: CustomButtonTouchBarItem {
    init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier, title: SystemMetrics.unsupportedBoardLabel)
        image = StudioControlStyle.image("boardTemperature")
        view.toolTip = "Motherboard sensor unavailable in this build. CPU, GPU, PMU, and package temperatures are not substituted."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
