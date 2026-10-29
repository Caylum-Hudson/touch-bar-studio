import AppKit
import ApplicationServices

enum ResolveColorDialParameter: String, CaseIterable {
    case lift, gamma, gain
    var title: String { rawValue.capitalized }
}

enum ResolveColorDialChannel: String, CaseIterable {
    case y = "Y", red = "R", green = "G", blue = "B"
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum ResolveColorDialSensitivity: String, CaseIterable {
    case fine, normal, coarse
    var rangeFractionPerPoint: Double {
        switch self {
        case .fine: return 0.0001
        case .normal: return 0.0005
        case .coarse: return 0.001
        }
    }
}

struct ResolveColorDialAccumulator {
    private(set) var rawRemainder = 0.0
    static let maximumRawStepsPerUpdate = 8

    mutating func advance(points: Double, range: Double, sensitivity: ResolveColorDialSensitivity) -> Int {
        guard points.isFinite, range.isFinite, range > 0 else { return 0 }
        let next = rawRemainder + points * range * sensitivity.rangeFractionPerPoint
        guard next.isFinite else { rawRemainder = 0; return points < 0 ? -Self.maximumRawStepsPerUpdate : Self.maximumRawStepsPerUpdate }
        if abs(next) >= Double(Self.maximumRawStepsPerUpdate + 1) {
            rawRemainder = 0
            return next < 0 ? -Self.maximumRawStepsPerUpdate : Self.maximumRawStepsPerUpdate
        }
        let epsilon = next < 0 ? -1e-9 : 1e-9
        let steps = Int((next + epsilon).rounded(.towardZero))
        rawRemainder = next - Double(steps)
        return steps
    }

    mutating func reset() { rawRemainder = 0 }
}

enum ResolveColorDialReleasePolicy {
    static func shouldWaitForWrite(pendingRawStep: Int, writeScheduled: Bool) -> Bool {
        pendingRawStep != 0 || writeScheduled
    }
}

enum ResolveDialTextLayout {
    static func availableWidth(viewWidth: CGFloat, leadingX: CGFloat, trailingInset: CGFloat = 4) -> CGFloat {
        max(0,viewWidth-leadingX-trailingInset)
    }
}

struct ResolveColorSliderSnapshot {
    let minimum: Double
    let maximum: Double
    let value: Double
    let settable: Bool
    let displayValue: String?
}

struct ResolveColorBarGroupSnapshot {
    let heading: String
    let sliders: [ResolveColorSliderSnapshot]
    let sliderChildIndices: [Int]
}

struct ResolveColorBarSiblingSnapshot {
    let role: String
    let label: String
    let minimum: Double?
    let maximum: Double?
    let value: Double?
    let settable: Bool
}

struct ResolveColorBarStructureSnapshot {
    let selectedTabs: [String]
    var unrelatedSelectedTabs: [String] = []
    let primariesGroupCount: Int
    let groups: [ResolveColorBarGroupSnapshot]
}

enum ResolveColorDialStructure {
    static let requiredTabs = ["ColorWheels", "ColorBars", "Log"]
    static let requiredParameters = ["Lift", "Gamma", "Gain"]

    static func numericValues(_ text: String) -> [String] {
        let pattern = #"[-+]?(?:\d+\.\d+|\d+)"#
        guard let expression = try? NSRegularExpression(pattern:pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex,in:text)
        return expression.matches(in:text,range:range).compactMap { Range($0.range,in:text).map { String(text[$0]) } }
    }

    static func canonicalModeTab(_ label: String) -> String? {
        switch label.trimmingCharacters(in:.whitespacesAndNewlines) {
        case "Color Bars": return "ColorBars"
        case "Color Wheels": return "ColorWheels"
        case "Log Wheels", "Log": return "Log"
        default: return nil
        }
    }

    static func selectedModeTabs(from checkboxes: [(label:String,selected:Bool)]) -> [String]? {
        let recognized = checkboxes.compactMap { checkbox -> (String,Bool)? in
            canonicalModeTab(checkbox.label).map { ($0,checkbox.selected) }
        }
        guard recognized.count == 3,
              recognized.filter({ $0.1 }).count == 1,
              Set(recognized.map { $0.0 }) == Set(requiredTabs) else { return nil }
        return recognized.filter { $0.1 }.map { $0.0 }
    }

    static func groups(from siblings: [ResolveColorBarSiblingSnapshot]) -> [ResolveColorBarGroupSnapshot]? {
        let markers: [(String,Int)] = siblings.enumerated().compactMap { index,node in
            if ["Lift","Gain"].contains(node.label) { return (node.label,index) }
            if node.label.hasSuffix("Gamma") { return ("Gamma",index) }
            if node.label.hasSuffix("Offset") { return ("Offset",index) }
            return nil
        }
        guard markers.map(\.0) == ["Lift","Gamma","Gain","Offset"] else { return nil }
        var result: [ResolveColorBarGroupSnapshot] = []
        for (markerIndex,(heading,markerPosition)) in markers.enumerated() {
            let start = markerPosition + 1
            let end = markerIndex + 1 < markers.count ? markers[markerIndex + 1].1 : siblings.endIndex
            guard start <= end else { return nil }
            let section = siblings[start..<end]
            let indices = section.indices.filter { siblings[$0].role == "AXSlider" }
            let expected = heading == "Offset" ? 3 : 4
            guard indices.count == expected else { return nil }
            let displayText: String
            switch heading {
            case "Lift", "Gain":
                guard markerIndex + 1 < markers.count else { return nil }
                let markerLabel = siblings[markers[markerIndex + 1].1].label
                guard numericValues(markerLabel).count == 4 else { return nil }
                displayText = markerLabel
            case "Gamma":
                let values = section.filter { $0.role == "AXStaticText" && numericValues($0.label).count == 4 }
                guard values.count == 1, let value = values.first else { return nil }
                displayText = value.label
            default: displayText = ""
            }
            let displayValues = numericValues(displayText)
            let sliders = indices.enumerated().compactMap { channel,index -> ResolveColorSliderSnapshot? in
                let item = siblings[index]
                guard let minimum = item.minimum, let maximum = item.maximum, let value = item.value,
                      minimum.isFinite, maximum.isFinite, minimum < maximum,
                      value.isFinite, value >= minimum, value <= maximum, item.settable else { return nil }
                return ResolveColorSliderSnapshot(minimum:minimum,maximum:maximum,value:value,settable:item.settable,displayValue:displayValues.indices.contains(channel) ? displayValues[channel] : nil)
            }
            guard sliders.count == expected else { return nil }
            result.append(ResolveColorBarGroupSnapshot(heading:heading,sliders:sliders,sliderChildIndices:indices))
        }
        return result
    }

    static func gammaDisplayLabel(from siblings: [(role:String,label:String)]) -> String? {
        let matches = siblings.filter { $0.role == "AXStaticText" && numericValues($0.label).count == 4 }
        return matches.count == 1 ? matches[0].label : nil
    }

    static func slider(in snapshot: ResolveColorBarStructureSnapshot, parameter: ResolveColorDialParameter, channel: ResolveColorDialChannel) -> ResolveColorSliderSnapshot? {
        guard snapshot.primariesGroupCount == 1,
              snapshot.selectedTabs.filter({ requiredTabs.contains($0) }) == ["ColorBars"] else { return nil }
        let matches = snapshot.groups.filter { $0.heading == parameter.title }
        guard matches.count == 1, let group = matches.first, group.sliders.count == 4,
              requiredParameters.allSatisfy({ heading in snapshot.groups.filter { $0.heading == heading }.count == 1 }),
              group.sliders.allSatisfy({ $0.settable && $0.minimum.isFinite && $0.maximum.isFinite && $0.minimum < $0.maximum && $0.value.isFinite && $0.value >= $0.minimum && $0.value <= $0.maximum }) else { return nil }
        return group.sliders[channel.index]
    }
}

private struct PendingResolveColorWrite {
    let parameter: ResolveColorDialParameter
    let channel: ResolveColorDialChannel
    var rawDelta: Int
    let canWrite: () -> Bool
    var completions: [(String?) -> Void]
}

private struct ResolveAXNode {
    let element: AXUIElement
    let role: String
    let label: String
    let value: CFTypeRef?
    let children: [ResolveAXNode]

    var descendants: [ResolveAXNode] { [self] + children.flatMap(\.descendants) }
}

/// One reader is shared by every dial. Polling uses a short cache, while writes always
/// rebuild the focused window tree and resolve a fresh slider before changing it.
final class ResolveColorDialReader {
    static let shared = ResolveColorDialReader()
    private var cachedAt = Date.distantPast
    private var cachedValues: [String: (Double, Double, Double, String?)] = [:]
    private var cachedStatus = "Focus Resolve"
    private var refreshInFlight = false
    private var pendingWrites: [String: PendingResolveColorWrite] = [:]
    private var writeFlushScheduled = false
    private let stateLock = NSLock()
    private let workQueue = DispatchQueue(label:"nz.caylum.touchbarstudio.resolve-color-bars",qos:.utility)

    func sample(parameter: ResolveColorDialParameter, channel: ResolveColorDialChannel) -> (value: Double, minimum: Double, maximum: Double, valueText: String?, status: String) {
        guard AppSettings.customResolveInteractionAllowed else { return (0,0,1,nil,"Use custom Color bar") }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.blackmagic-design.DaVinciResolve" else { return (0,0,1,nil,"Focus Resolve") }
        var shouldRefresh = false
        stateLock.lock()
        if Date().timeIntervalSince(cachedAt) >= 0.3 && !refreshInFlight {
            refreshInFlight = true
            shouldRefresh = true
        }
        let key = "\(parameter.rawValue):\(channel.rawValue)"
        let reading = cachedValues[key]
        let status = cachedStatus
        stateLock.unlock()
        if shouldRefresh { workQueue.async { [weak self] in self?.refreshCache() } }
        guard let reading else { return (0,0,1,nil,status) }
        return (reading.0,reading.1,reading.2,reading.3,status)
    }

    func apply(rawStep: Int, parameter: ResolveColorDialParameter, channel: ResolveColorDialChannel, controlIdentifier: String, canWrite: @escaping () -> Bool, completion: @escaping (String?) -> Void) {
        guard rawStep != 0 else { completion(nil); return }
        let key = controlIdentifier
        stateLock.lock()
        if var pending = pendingWrites[key] {
            pending.rawDelta = min(ResolveColorDialAccumulator.maximumRawStepsPerUpdate,max(-ResolveColorDialAccumulator.maximumRawStepsPerUpdate,pending.rawDelta + rawStep))
            pending.completions.append(completion)
            pendingWrites[key] = pending
        } else { pendingWrites[key] = PendingResolveColorWrite(parameter:parameter,channel:channel,rawDelta:rawStep,canWrite:canWrite,completions:[completion]) }
        let shouldSchedule = !writeFlushScheduled
        writeFlushScheduled = true
        stateLock.unlock()
        if shouldSchedule { workQueue.asyncAfter(deadline:.now() + 0.08) { [weak self] in self?.flushWrites() } }
    }

    func cancelWrites(controlIdentifier: String) {
        stateLock.lock()
        pendingWrites.removeValue(forKey:controlIdentifier)
        stateLock.unlock()
    }

    func cancelAllWrites() {
        stateLock.lock()
        let writes=pendingWrites
        pendingWrites.removeAll(keepingCapacity:true)
        stateLock.unlock()
        for write in writes.values { write.completions.forEach { completion in DispatchQueue.main.async { completion("Use custom Color bar") } } }
    }

    private func flushWrites() {
        stateLock.lock()
        let writes = pendingWrites
        pendingWrites.removeAll(keepingCapacity:true)
        writeFlushScheduled = false
        stateLock.unlock()
        guard !writes.isEmpty else { return }
        let statuses = applyBatch(writes)
        stateLock.lock()
        cachedAt = .distantPast
        stateLock.unlock()
        for (key,write) in writes {
            let status = statuses[key] ?? "Color control unavailable"
            write.completions.forEach { completion in DispatchQueue.main.async { completion(status.isEmpty ? nil : status) } }
        }
    }

    private func applyBatch(_ writes: [String: PendingResolveColorWrite]) -> [String:String] {
        var statuses: [String:String] = [:]
        guard AppSettings.customResolveInteractionAllowed else { return Dictionary(uniqueKeysWithValues:writes.keys.map { ($0,"Use custom Color bar") }) }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier == "com.blackmagic-design.DaVinciResolve" else { return Dictionary(uniqueKeysWithValues:writes.keys.map { ($0,"Focus Resolve") }) }
        guard AXIsProcessTrusted() else { return Dictionary(uniqueKeysWithValues:writes.keys.map { ($0,"Allow Accessibility") }) }
        let process = application.processIdentifier
        guard ResolvePageDetection.detect(processIdentifier: process).page == "color" else { return Dictionary(uniqueKeysWithValues:writes.keys.map { ($0,"Open Color page") }) }
        for (key,write) in writes {
            guard write.canWrite(), AppSettings.customResolveInteractionAllowed else { statuses[key] = "Use custom Color bar"; continue }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == process,
                  ResolvePageDetection.detect(processIdentifier:process).page == "color" else { statuses[key] = "Open Color page"; continue }
            guard let resolved = resolve(processIdentifier:process) else { statuses[key] = "Open Color Bars"; continue }
            let parameter = write.parameter
            let channel = write.channel
            guard let target = ResolveColorDialStructure.slider(in:resolved.snapshot,parameter:parameter,channel:channel),
                  let element = resolved.sliderElements["\(parameter.rawValue):\(channel.index)"],
                  let current = axNumber(element,kAXValueAttribute),
                  current >= target.minimum, current <= target.maximum,
                  isSettable(element,kAXValueAttribute) else { statuses[key] = "Open Color Bars"; continue }
            guard write.canWrite(), AppSettings.customResolveInteractionAllowed, NSWorkspace.shared.frontmostApplication?.processIdentifier == process,
                  ResolvePageDetection.detect(processIdentifier:process).page == "color" else { statuses[key] = ""; continue }
            let rawStep = min(ResolveColorDialAccumulator.maximumRawStepsPerUpdate,max(-ResolveColorDialAccumulator.maximumRawStepsPerUpdate,write.rawDelta))
            let next = min(target.maximum,max(target.minimum,current + Double(rawStep)))
            statuses[key] = AXUIElementSetAttributeValue(element,kAXValueAttribute as CFString,NSNumber(value:next)) == .success ? "" : "Color control unavailable"
        }
        return statuses
    }

    private func refreshCache() {
        var values: [String: (Double, Double, Double, String?)] = [:]
        var status = "Open Color Bars"
        guard AppSettings.customResolveInteractionAllowed else {
            updateCache(values,status:"Use custom Color bar")
            return
        }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier == "com.blackmagic-design.DaVinciResolve" else {
            status = "Focus Resolve"
            updateCache(values,status:status)
            return
        }
        guard AXIsProcessTrusted() else {
            status = "Allow Accessibility"
            updateCache(values,status:status)
            return
        }
        guard ResolvePageDetection.detect(processIdentifier:application.processIdentifier).page == "color" else {
            status = "Open Color page"
            updateCache(values,status:status)
            return
        }
        guard let resolved = resolve(processIdentifier:application.processIdentifier) else {
            status = "Check Color Bars"
            updateCache(values,status:status)
            return
        }
        for parameter in ResolveColorDialParameter.allCases {
            for channel in ResolveColorDialChannel.allCases {
                if let slider = ResolveColorDialStructure.slider(in:resolved.snapshot,parameter:parameter,channel:channel) {
                    values["\(parameter.rawValue):\(channel.rawValue)"] = (slider.value,slider.minimum,slider.maximum,slider.displayValue)
                }
            }
        }
        status = values.isEmpty ? "Open Color Bars" : "Ready"
        updateCache(values,status:status)
    }

    private func updateCache(_ values: [String: (Double, Double, Double, String?)], status: String) {
        stateLock.lock()
        cachedAt = Date()
        cachedValues = values
        cachedStatus = status
        refreshInFlight = false
        stateLock.unlock()
    }

    private func resolve(processIdentifier: pid_t) -> (snapshot: ResolveColorBarStructureSnapshot, sliderElements: [String:AXUIElement])? {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application,0.02)
        let deadline = Date().addingTimeInterval(1.0)
        var budget = 1200
        guard let main = axElement(application,kAXMainWindowAttribute),
              let focused = axElement(application,kAXFocusedWindowAttribute), CFEqual(main,focused),
              axString(main,kAXRoleAttribute) == kAXWindowRole,
              axString(main,kAXSubroleAttribute) == kAXStandardWindowSubrole,
              Date() < deadline, let tree = buildNode(main,depth:0,budget:&budget,deadline:deadline) else { return nil }
        let nodes = tree.descendants
        let primaryContainers = nodes.filter { node in
            node.children.contains(where: { $0.label == "Primaries - Color Bars" })
                && node.children.filter({ $0.role == kAXCheckBoxRole && ResolveColorDialStructure.canonicalModeTab($0.label) != nil }).count == 3
        }
        guard primaryContainers.count == 1, let primary = primaryContainers.first else { return nil }
        let directTabs = primary.children.filter { $0.role == kAXCheckBoxRole }
        guard let selectedTabs = ResolveColorDialStructure.selectedModeTabs(from:directTabs.map { ($0.label,($0.value as? NSNumber)?.boolValue == true) }),
              selectedTabs == ["ColorBars"] else { return nil }
        let panelCandidates = primary.descendants.filter { node in
            let children = node.children
            return children.contains(where: { $0.label == "Lift" })
                && children.contains(where: { $0.label.hasSuffix("Gamma") })
                && children.contains(where: { $0.label == "Gain" })
                && children.contains(where: { $0.label.hasSuffix("Offset") })
        }
        guard panelCandidates.count == 1, let panel = panelCandidates.first else { return nil }
        let siblings = panel.children.map { node -> ResolveColorBarSiblingSnapshot in
            guard node.role == kAXSliderRole else { return ResolveColorBarSiblingSnapshot(role:node.role,label:node.label,minimum:nil,maximum:nil,value:nil,settable:false) }
            return ResolveColorBarSiblingSnapshot(
                role:node.role,
                label:node.label,
                minimum:axNumber(node.element,kAXMinValueAttribute),
                maximum:axNumber(node.element,kAXMaxValueAttribute),
                value:axNumber(node.element,kAXValueAttribute),
                settable:isSettable(node.element,kAXValueAttribute)
            )
        }
        guard let groups = ResolveColorDialStructure.groups(from:siblings) else { return nil }
        var sliderElements: [String:AXUIElement] = [:]
        for group in groups where ResolveColorDialStructure.requiredParameters.contains(group.heading) {
            for (channel,index) in group.sliderChildIndices.enumerated() where channel < 4 {
                sliderElements["\(group.heading.lowercased()):\(channel)"] = panel.children[index].element
            }
        }
        let unrelatedTabs = nodes.filter { ResolveColorDialStructure.requiredTabs.contains($0.label) && ($0.value as? NSNumber)?.boolValue == true }.map(\.label)
        let snapshot = ResolveColorBarStructureSnapshot(selectedTabs:selectedTabs,unrelatedSelectedTabs:unrelatedTabs,primariesGroupCount:primaryContainers.count,groups:groups)
        return (snapshot,sliderElements)
    }

    private func buildNode(_ element: AXUIElement, depth: Int, budget: inout Int, deadline: Date) -> ResolveAXNode? {
        guard depth < 12, budget > 0, Date() < deadline else { return nil }
        budget -= 1
        let role = axString(element,kAXRoleAttribute) ?? ""
        let label = firstNonEmpty(axString(element,kAXTitleAttribute),axString(element,kAXDescriptionAttribute),axValue(element,kAXValueAttribute) as? String) ?? ""
        let value = axValue(element,kAXValueAttribute)
        guard Date() < deadline else { return nil }
        let childElements = (axValue(element,kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(160)
        let children = childElements.compactMap { buildNode($0,depth:depth + 1,budget:&budget,deadline:deadline) }
        return ResolveAXNode(element:element,role:role,label:label,value:value,children:children)
    }

    private func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,attribute as CFString,&value) == .success else { return nil }
        return value
    }
    private func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = axValue(element,attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return value as! AXUIElement
    }
    private func axString(_ element: AXUIElement, _ attribute: String) -> String? { axValue(element,attribute) as? String }
    private func axNumber(_ element: AXUIElement, _ attribute: String) -> Double? {
        guard let value = axValue(element,attribute) as? NSNumber else { return nil }
        let number = value.doubleValue
        return number.isFinite ? number : nil
    }
    private func firstNonEmpty(_ values: String?...) -> String? { values.compactMap { $0?.trimmingCharacters(in:.whitespacesAndNewlines) }.first { !$0.isEmpty } }
    private func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element,attribute as CFString,&settable) == .success && settable.boolValue
    }
}

final class ResolveDialView: NSView {
    var title = "Lift Y"
    var valueText = "—"
    var value = 0.5
    var status = "Open Color Bars"
    var onDragStart: (() -> Void)?
    var onDelta: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onDragCancel: (() -> Void)?
    private var lastX: CGFloat?
    var minimumContentWidth: CGFloat = 90 { didSet { invalidateIntrinsicContentSize() } }
    override var intrinsicContentSize: NSSize { NSSize(width:minimumContentWidth,height:30) }

    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        setContentCompressionResistancePriority(.required,for:.horizontal)
        allowedTouchTypes = .direct
        let gesture = NSPanGestureRecognizer(target:self,action:#selector(drag(_:)))
        gesture.allowedTouchTypes = .direct
        gesture.numberOfTouchesRequired = 1
        addGestureRecognizer(gesture)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func drag(_ recognizer: NSPanGestureRecognizer) {
        let x = recognizer.location(in:self).x
        if recognizer.state == .began { lastX = x; onDragStart?(); return }
        guard let lastX else { return }
        if recognizer.state == .changed { onDelta?(x - lastX); self.lastX = x }
        if recognizer.state == .ended { self.lastX = nil; onDragEnd?() }
        if recognizer.state == .cancelled || recognizer.state == .failed { self.lastX = nil; if let cancel=onDragCancel { cancel() } else { onDragEnd?() } }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds
        let enabled = status == "Ready"
        let center = CGPoint(x:14,y:bounds.midY)
        let ring = NSBezierPath(ovalIn:NSRect(x:center.x - 10,y:center.y - 10,width:20,height:20))
        (enabled ? NSColor.controlAccentColor.withAlphaComponent(0.75) : NSColor.secondaryLabelColor.withAlphaComponent(0.5)).setStroke()
        ring.lineWidth = 2
        ring.stroke()
        let angle = CGFloat(value) * .pi * 1.5 - .pi * 0.75
        let indicator = NSBezierPath()
        indicator.move(to:center)
        indicator.line(to:CGPoint(x:center.x + cos(angle) * 7,y:center.y + sin(angle) * 7))
        indicator.lineWidth = 2
        (enabled ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setStroke()
        indicator.stroke()
        let name = status == "Ready" ? title : status
        let textWidth=ResolveDialTextLayout.availableWidth(viewWidth:bounds.width,leadingX:30)
        let textBounds=NSRect(x:30,y:bounds.midY - 11,width:textWidth,height:22)
        let options:NSString.DrawingOptions=[.usesLineFragmentOrigin,.truncatesLastVisibleLine]
        (name as NSString).draw(with:textBounds,options:options,attributes:[.font:NSFont.systemFont(ofSize:9,weight:.medium),.foregroundColor:NSColor.labelColor],context:nil)
        if enabled { (valueText as NSString).draw(with:NSRect(x:30,y:bounds.midY - 11,width:textWidth,height:11),options:options,attributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:9,weight:.regular),.foregroundColor:NSColor.secondaryLabelColor],context:nil) }
    }
}

final class ResolveColorDialTouchBarItem: NSCustomTouchBarItem {
    private let parameter: ResolveColorDialParameter
    private let channel: ResolveColorDialChannel
    private let dial: ResolveDialView
    private let controlIdentifier: String
    private let sensitivity: ResolveColorDialSensitivity
    private var timer: Timer?
    private var pendingRawStep = 0
    private var accumulator = ResolveColorDialAccumulator()
    private var writeScheduledGeneration: UInt64?
    private let dragLock = NSLock()
    private var isDragging = false
    private var dragGeneration: UInt64 = 0
    private var endingDrag = false

    init(identifier: NSTouchBarItem.Identifier, parameter: String, channel: String, sensitivity: String) {
        self.parameter = ResolveColorDialParameter(rawValue:parameter) ?? .lift
        self.channel = ResolveColorDialChannel(rawValue:channel) ?? .y
        self.controlIdentifier = identifier.rawValue
        self.sensitivity = ResolveColorDialSensitivity(rawValue:sensitivity) ?? .fine
        dial = ResolveDialView(frame:NSRect(x:0,y:0,width:90,height:30))
        super.init(identifier:identifier)
        view = dial
        dial.title = "\(self.parameter.title) \(self.channel.rawValue)"
        dial.onDragStart = { [weak self] in self?.beginDrag() }
        dial.onDelta = { [weak self] points in self?.queueDelta(points) }
        dial.onDragEnd = { [weak self] in self?.finishDrag() }
        dial.onDragCancel = { [weak self] in self?.endDrag() }
        timer = Timer.scheduledTimer(withTimeInterval:0.3,repeats:true) { [weak self] _ in self?.refresh() }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func cancelStudioInteraction() { endDrag() }
    deinit {
        timer?.invalidate()
        ResolveColorDialReader.shared.cancelWrites(controlIdentifier:controlIdentifier)
    }

    private func refresh() {
        let sample = ResolveColorDialReader.shared.sample(parameter:parameter,channel:channel)
        dial.status = sample.status
        if sample.status == "Ready" {
            dial.valueText = sample.valueText ?? String(format:"raw %.3f",sample.value)
            dial.value = (sample.value - sample.minimum) / (sample.maximum - sample.minimum)
        } else { dial.valueText = "—" }
        if sample.status != "Ready", isDraggingNow { endDrag() }
        dial.setAccessibilityLabel("\(parameter.title) \(channel.rawValue) color control")
        dial.setAccessibilityValue(dial.status == "Ready" ? dial.valueText : dial.status)
        dial.setAccessibilityHelp("Drag horizontally to adjust the \(sensitivity.rawValue) relative to the raw slider range. Resolve Color page and Color Bars must be open.")
        dial.needsDisplay = true
    }

    private func queueDelta(_ points: CGFloat) {
        guard points.isFinite, isDraggingNow, !endingDrag else { return }
        let sample = ResolveColorDialReader.shared.sample(parameter:parameter,channel:channel)
        guard sample.status == "Ready" else { endDrag(); return }
        let rawStep = accumulator.advance(points:Double(points),range:sample.maximum-sample.minimum,sensitivity:sensitivity)
        guard rawStep != 0 else { return }
        pendingRawStep = min(ResolveColorDialAccumulator.maximumRawStepsPerUpdate,max(-ResolveColorDialAccumulator.maximumRawStepsPerUpdate,pendingRawStep + rawStep))
        scheduleWrite()
    }

    private func beginDrag() {
        dragLock.lock()
        dragGeneration &+= 1
        isDragging = true
        dragLock.unlock()
        endingDrag = false
        pendingRawStep = 0
        accumulator.reset()
        writeScheduledGeneration = nil
    }

    private func endDrag() {
        dragLock.lock()
        isDragging = false
        dragGeneration &+= 1
        dragLock.unlock()
        pendingRawStep = 0
        accumulator.reset()
        writeScheduledGeneration = nil
        endingDrag = false
        ResolveColorDialReader.shared.cancelWrites(controlIdentifier:controlIdentifier)
        refresh()
    }

    private func finishDrag() {
        endingDrag = true
        if ResolveColorDialReleasePolicy.shouldWaitForWrite(pendingRawStep:pendingRawStep,writeScheduled:writeScheduledGeneration != nil) {
            if pendingRawStep != 0 { scheduleWrite() }
            return
        }
        endDrag()
    }

    private var isDraggingNow: Bool {
        dragLock.lock(); defer { dragLock.unlock() }
        return isDragging
    }

    private var currentDragGeneration: UInt64 {
        dragLock.lock(); defer { dragLock.unlock() }
        return dragGeneration
    }

    private func isCurrentDrag(_ token: UInt64) -> Bool {
        AppSettings.customResolveInteractionAllowed && dragGenerationMatches(token)
    }

    private func dragGenerationMatches(_ token: UInt64) -> Bool {
        dragLock.lock(); defer { dragLock.unlock() }
        return ResolveDragGenerationPolicy.shouldContinue(dragging:isDragging,currentGeneration:dragGeneration,capturedGeneration:token)
    }

    private func scheduleWrite() {
        guard writeScheduledGeneration == nil else { return }
        guard pendingRawStep != 0 else { return }
        let generation = currentDragGeneration
        writeScheduledGeneration = generation
        DispatchQueue.main.asyncAfter(deadline:.now() + 0.02) { [weak self] in
            guard let self else { return }
            guard self.isCurrentDrag(generation) else {
                if self.dragGenerationMatches(generation) { self.endDrag() }
                return
            }
            let rawStep = self.pendingRawStep
            self.pendingRawStep = 0
            ResolveColorDialReader.shared.apply(rawStep:rawStep,parameter:self.parameter,channel:self.channel,controlIdentifier:self.controlIdentifier,canWrite:{ [weak self] in
                guard let self else { return false }
                return self.isCurrentDrag(generation)
            }) { [weak self] status in
                guard let self else { return }
                guard self.dragGenerationMatches(generation) else { return }
                guard AppSettings.customResolveInteractionAllowed else { self.dial.status = "Use custom Color bar"; self.endDrag(); return }
                if let status { self.dial.status = status }
                if status != nil { self.endDrag() }
                else { self.writeScheduledGeneration = nil }
                self.refresh()
                if self.endingDrag, self.pendingRawStep == 0 { self.endDrag(); return }
                self.scheduleWrite()
            }
        }
    }
}
