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
            guard usage.isFinite else {
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
            let attrTitle = NSMutableAttributedString.init(attributedString: String(format: "%.1f%%", usage).defaultTouchbarAttributedString)
            if let color = color {
                attrTitle.addAttributes([.foregroundColor: color], range: NSRange(location: 0, length: attrTitle.length))
            }
            self.attributedTitle = attrTitle
            self.backgroundColor = bgColor
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
        refreshQueue?.suspend()
        refreshQueue = nil
    }
}

/// A cached system-wide sample shared by all metrics controls. Calls are
/// serialized and coalesced so multiple widgets never enumerate sensors every
/// refresh tick.
struct SystemMetricsSnapshot {
    let ramUsedBytes: UInt64?
    let ramTotalBytes: UInt64
    let gpuUtilization: Double?
}

enum SystemMetrics {
    enum Monitor: Hashable { case ram, gpu }
    static let didUpdate = Notification.Name("TouchBarStudio.SystemMetricsDidUpdate")
    private static let queue = DispatchQueue(label: "mtmr.system-metrics", qos: .utility)
    // mach_host_self() returns a send right; keep one for this sampler's
    // lifetime instead of requesting another right on every RAM refresh.
    private static let hostPort = mach_host_self()
    private static var timer: DispatchSourceTimer?
    private static var monitorCounts: [Monitor: Int] = [:]
    private static var cached = SystemMetricsSnapshot(ramUsedBytes: nil, ramTotalBytes: ProcessInfo.processInfo.physicalMemory, gpuUtilization: nil)

    static func startMonitoring(_ monitor: Monitor) {
        queue.async {
            monitorCounts[monitor, default: 0] += 1
            if timer == nil {
                let source = DispatchSource.makeTimerSource(queue: queue)
                source.schedule(deadline: .now(), repeating: 2)
                source.setEventHandler {
                    cached = readSnapshot(includeRAM: (monitorCounts[.ram] ?? 0) > 0, includeGPU: (monitorCounts[.gpu] ?? 0) > 0)
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
            guard monitorCounts.isEmpty else { return }
            timer?.cancel()
            timer = nil
        }
    }

    static func snapshot() -> SystemMetricsSnapshot { queue.sync { cached } }
    static var monitorSubscriberCount: Int { queue.sync { monitorCounts.values.reduce(0, +) } }
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

    static let unsupportedBoardLabel = "Board —"

    private static func readSnapshot(includeRAM: Bool, includeGPU: Bool) -> SystemMetricsSnapshot {
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
        return SystemMetricsSnapshot(ramUsedBytes: used, ramTotalBytes: total, gpuUtilization: includeGPU ? readGPUUtilization() : nil)
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
}

class SystemMetricBarItem: CustomButtonTouchBarItem {
    private var observer: NSObjectProtocol?
    private let monitor: SystemMetrics.Monitor

    init(identifier: NSTouchBarItem.Identifier, title: String, symbol: String, monitor: SystemMetrics.Monitor) {
        self.monitor = monitor
        super.init(identifier: identifier, title: title)
        image = StudioControlStyle.image(symbol)
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
    init(identifier: NSTouchBarItem.Identifier) { super.init(identifier: identifier, title: "RAM —", symbol: "ramUsage", monitor: .ram) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func refresh() {
        let sample = SystemMetrics.snapshot()
        let percent = SystemMetrics.ramPercent(used: sample.ramUsedBytes, total: sample.ramTotalBytes)
        display(percent.map { "RAM \($0)%" } ?? "RAM —", detail: SystemMetrics.ramDetail(used: sample.ramUsedBytes, total: sample.ramTotalBytes))
    }
}

final class GPUUsageBarItem: SystemMetricBarItem {
    init(identifier: NSTouchBarItem.Identifier) { super.init(identifier: identifier, title: "GPU —", symbol: "gpuUsage", monitor: .gpu) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func refresh() {
        let value = SystemMetrics.gpuPercent(SystemMetrics.snapshot().gpuUtilization)
        display(value.map { "GPU \($0)%" } ?? "GPU —", detail: value.map { "System-wide GPU device utilization: \($0)%. Multiple GPUs show the busiest device." } ?? "GPU utilization unavailable: this Mac did not expose an IOAccelerator device utilization counter.")
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
