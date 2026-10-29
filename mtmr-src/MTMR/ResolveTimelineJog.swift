import AppKit
import ApplicationServices

enum ResolveTimelineJogSensitivity: String, CaseIterable {
    case fine, normal, coarse
    var framesPerPoint: Double {
        switch self {
        case .fine: return 0.08
        case .normal: return 0.20
        case .coarse: return 0.45
        }
    }
}

struct ResolveTimelineJogAccumulator {
    private(set) var remainder = 0.0
    static let maximumFramesPerUpdate = 4

    mutating func advance(points: Double, sensitivity: ResolveTimelineJogSensitivity) -> Int {
        guard points.isFinite else { return 0 }
        let next = remainder + points * sensitivity.framesPerPoint
        guard next.isFinite else { remainder = 0; return points < 0 ? -Self.maximumFramesPerUpdate : Self.maximumFramesPerUpdate }
        if abs(next) >= Double(Self.maximumFramesPerUpdate + 1) {
            remainder = 0
            return next < 0 ? -Self.maximumFramesPerUpdate : Self.maximumFramesPerUpdate
        }
        remainder = next
        let whole = Int(remainder.rounded(.towardZero))
        let bounded = min(Self.maximumFramesPerUpdate,max(-Self.maximumFramesPerUpdate,whole))
        remainder = abs(whole) > Self.maximumFramesPerUpdate ? 0 : remainder - Double(bounded)
        return bounded
    }

    mutating func reset() { remainder = 0 }
}

enum ResolveDragGenerationPolicy {
    static func shouldContinue(dragging: Bool, currentGeneration: UInt64, capturedGeneration: UInt64, touchBarEnabled: Bool = true) -> Bool {
        touchBarEnabled && dragging && currentGeneration == capturedGeneration
    }
}

enum ResolveJogInFlightPolicy {
    static func shouldRelease(activeGeneration: UInt64?, completedGeneration: UInt64) -> Bool {
        activeGeneration == completedGeneration
    }
}

struct ResolveMenuNodeSnapshot {
    let role: String
    let title: String
    let enabled: Bool
    let children: [ResolveMenuNodeSnapshot]
}

enum ResolveTimelineMenuPath {
    static func pressTargets(in menuBar: ResolveMenuNodeSnapshot, titles: [String]) -> [ResolveMenuNodeSnapshot] {
        guard let first = titles.first, titles.count >= 2,
              let top = uniqueItem(first,in:menuBar.children,roles:["AXMenuBarItem"]), top.enabled else { return [] }
        var current = top
        for title in titles.dropFirst() {
            let menus = current.children.filter { $0.role == "AXMenu" }
            guard menus.count == 1,
                  let item = uniqueItem(title,in:menus[0].children,roles:["AXMenuItem"]),
                  item.enabled else { return [] }
            current = item
        }
        return [current]
    }

    private static func uniqueItem(_ title: String, in nodes: [ResolveMenuNodeSnapshot], roles: [String]) -> ResolveMenuNodeSnapshot? {
        let matches = nodes.filter { roles.contains($0.role) && $0.title == title }
        return matches.count == 1 ? matches.first : nil
    }
}

private enum ResolveTimelineMenuAccess {
    static let bundleIdentifier = "com.blackmagic-design.DaVinciResolve"

    static func focusTimeline(processIdentifier: pid_t, canContinue: () -> Bool) -> Bool {
        guard isSafeEditFocus(processIdentifier) else { return false }
        return pressPath(["Workspace","Active Panel Selection","Timeline"],processIdentifier:processIdentifier,canContinue:canContinue)
    }

    static func stepFrame(reverse: Bool, processIdentifier: pid_t, canContinue: () -> Bool) -> Bool {
        guard isSafeEditFocus(processIdentifier) else { return false }
        let direction = reverse ? "Frame Reverse" : "Frame Forward"
        return pressPath(["Playback","Step One",direction],processIdentifier:processIdentifier,canContinue:canContinue)
    }

    static func isSafeEditFocus(_ processIdentifier: pid_t) -> Bool {
        guard contextIsActive(processIdentifier) else { return false }
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application,0.05)
        guard let focused = axElement(application,kAXFocusedUIElementAttribute) else { return false }
        let role = axString(focused,kAXRoleAttribute) ?? ""
        return !["AXTextField","AXTextArea","AXSearchField","AXComboBox","AXDialog","AXSheet","AXMenu","AXMenuItem"].contains(role)
    }

    private static func pressPath(_ titles: [String], processIdentifier: pid_t, canContinue: () -> Bool) -> Bool {
        guard !titles.isEmpty, contextIsActive(processIdentifier), canContinue() else { return false }
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application,0.05)
        guard let menuBar = axElement(application,kAXMenuBarAttribute),
              let menuChildren = axArray(menuBar,kAXChildrenAttribute) else { return false }
        guard let target = resolveLeaf(in:menuChildren,titles:titles),
              canContinue(), contextIsActive(processIdentifier),
              isEnabled(target), canPress(target) else { return false }
        return AXUIElementPerformAction(target,kAXPressAction as CFString) == .success
    }

    private static func contextIsActive(_ processIdentifier: pid_t) -> Bool {
        guard AppSettings.touchBarEnabled,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier == processIdentifier,
              frontmost.bundleIdentifier == bundleIdentifier,
              AXIsProcessTrusted(),
              ResolvePageDetection.detect(processIdentifier:processIdentifier).page == "edit" else { return false }
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application,0.05)
        guard let main = axElement(application,kAXMainWindowAttribute),
              let focused = axElement(application,kAXFocusedWindowAttribute), CFEqual(main,focused),
              axString(main,kAXRoleAttribute) == kAXWindowRole,
              axString(main,kAXSubroleAttribute) == kAXStandardWindowSubrole else { return false }
        return true
    }

    private static func resolveLeaf(in menuBarChildren: [AXUIElement], titles: [String]) -> AXUIElement? {
        guard titles.count >= 2, let first = titles.first else { return nil }
        let topMatches = menuBarChildren.filter { axString($0,kAXRoleAttribute) == "AXMenuBarItem" && axTitle($0) == first }
        guard topMatches.count == 1, let top = topMatches.first, isEnabled(top) else { return nil }
        var current = top
        for title in titles.dropFirst() {
            guard let children = axArray(current,kAXChildrenAttribute) else { return nil }
            let menus = children.filter { axString($0,kAXRoleAttribute) == kAXMenuRole }
            guard menus.count == 1, let menu = menus.first,
                  let menuChildren = axArray(menu,kAXChildrenAttribute) else { return nil }
            let matches = menuChildren.filter { axString($0,kAXRoleAttribute) == kAXMenuItemRole && axTitle($0) == title }
            guard matches.count == 1, let next = matches.first, isEnabled(next) else { return nil }
            current = next
        }
        return current
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,attribute as CFString,&value) == .success else { return nil }
        return value
    }
    private static func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = axValue(element,attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return value as! AXUIElement
    }
    private static func axArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? { axValue(element,attribute) as? [AXUIElement] }
    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? { axValue(element,attribute) as? String }
    private static func axTitle(_ element: AXUIElement) -> String? {
        [axString(element,kAXTitleAttribute),axString(element,kAXDescriptionAttribute)]
            .compactMap { $0?.trimmingCharacters(in:.whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
    private static func isEnabled(_ element: AXUIElement) -> Bool { (axValue(element,kAXEnabledAttribute) as? NSNumber)?.boolValue == true }
    private static func canPress(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element,&names) == .success, let actions = names as? [String] else { return false }
        return actions.contains(kAXPressAction as String)
    }
}

final class ResolveTimelineJogView: NSView {
    var sensitivity = "normal"
    var status = "Edit timeline only"
    var onBegin: (() -> Void)?
    var onDelta: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var lastX: CGFloat?
    override var intrinsicContentSize: NSSize { NSSize(width:140,height:30) }

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
        switch recognizer.state {
        case .began: lastX = x; onBegin?()
        case .changed:
            if let lastX { onDelta?(x - lastX); self.lastX = x }
        case .ended, .cancelled, .failed: lastX = nil; onEnd?()
        default: break
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let centerY = bounds.midY
        let title = status == "Ready" ? "Timeline Jog" : status
        let options:NSString.DrawingOptions=[.usesLineFragmentOrigin,.truncatesLastVisibleLine]
        (title as NSString).draw(with:NSRect(x:5,y:centerY - 10,width:74,height:20),options:options,attributes:[.font:NSFont.systemFont(ofSize:9,weight:.medium),.foregroundColor:NSColor.labelColor],context:nil)
        let track = NSBezierPath()
        track.move(to:NSPoint(x:11,y:centerY - 7))
        track.line(to:NSPoint(x:79,y:centerY - 7))
        NSColor.secondaryLabelColor.withAlphaComponent(0.6).setStroke()
        track.lineWidth = 2
        track.stroke()
        let marker = NSBezierPath(ovalIn:NSRect(x:43,y:centerY - 11,width:8,height:8))
        (status == "Ready" ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setFill()
        marker.fill()
        (sensitivity.capitalized as NSString).draw(with:NSRect(x:82,y:centerY - 11,width:max(0,bounds.maxX-84),height:18),options:options,attributes:[.font:NSFont.systemFont(ofSize:8),.foregroundColor:NSColor.secondaryLabelColor],context:nil)
    }
}

final class ResolveTimelineJogTouchBarItem: NSCustomTouchBarItem {
    private let sensitivity: ResolveTimelineJogSensitivity
    private let jogView: ResolveTimelineJogView
    private let workQueue = DispatchQueue(label:"nz.caylum.touchbarstudio.resolve-timeline-jog",qos:.userInitiated)
    private let stateLock = NSLock()
    private var generation: UInt64 = 0
    private var dragging = false
    private var ready = false
    private var drainingGeneration: UInt64?
    private var pendingFrames = 0
    private var accumulator = ResolveTimelineJogAccumulator()

    init(identifier: NSTouchBarItem.Identifier, sensitivity: String) {
        self.sensitivity = ResolveTimelineJogSensitivity(rawValue:sensitivity) ?? .fine
        jogView = ResolveTimelineJogView(frame:NSRect(x:0,y:0,width:96,height:30))
        super.init(identifier:identifier)
        view = jogView
        jogView.sensitivity = self.sensitivity.rawValue
        jogView.onBegin = { [weak self] in self?.beginDrag() }
        jogView.onDelta = { [weak self] points in self?.addDelta(points) }
        jogView.onEnd = { [weak self] in self?.endDrag() }
        updateAccessibility()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func cancelStudioInteraction() { endDrag() }
    deinit { stateLock.lock(); dragging = false; generation &+= 1; stateLock.unlock() }

    private func beginDrag() {
        endSessionState()
        stateLock.lock(); generation &+= 1; let token = generation; dragging = true; stateLock.unlock()
        ready = false
        pendingFrames = 0
        drainingGeneration = nil
        accumulator.reset()
        setStatus("Selecting Timeline")
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == ResolveTimelineMenuAccess.bundleIdentifier else { setStatus("Open Resolve Edit"); endSessionState(); return }
        let pid = app.processIdentifier
        workQueue.async { [weak self] in
            guard let self else { return }
            let succeeded = ResolveTimelineMenuAccess.focusTimeline(processIdentifier:pid,canContinue:{ self.isCurrent(token) })
            DispatchQueue.main.async {
                guard self.generationMatches(token) else { return }
                guard AppSettings.touchBarEnabled else {
                    self.ready = false
                    self.pendingFrames = 0
                    self.accumulator.reset()
                    self.endSessionState()
                    self.setStatus("Touch Bar Off")
                    return
                }
                self.ready = succeeded
                self.setStatus(succeeded ? "Ready" : "Open Resolve Edit")
                if succeeded { self.drain(token:token,processIdentifier:pid) }
            }
        }
    }

    private func addDelta(_ points: CGFloat) {
        guard points.isFinite, isDraggingNow else { return }
        let frames = accumulator.advance(points:Double(points),sensitivity:sensitivity)
        pendingFrames = min(ResolveTimelineJogAccumulator.maximumFramesPerUpdate,max(-ResolveTimelineJogAccumulator.maximumFramesPerUpdate,pendingFrames + frames))
        stateLock.lock(); let token = generation; stateLock.unlock()
        if ready, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { drain(token:token,processIdentifier:pid) }
    }

    private func drain(token: UInt64, processIdentifier: pid_t) {
        guard ready, drainingGeneration == nil, pendingFrames != 0, isCurrent(token) else { return }
        let batch = pendingFrames
        pendingFrames = 0
        drainingGeneration = token
        workQueue.async { [weak self] in
            guard let self else { return }
            let reverse = batch < 0
            var success = ResolveTimelineMenuAccess.focusTimeline(processIdentifier:processIdentifier,canContinue:{ self.isCurrent(token) })
            if success {
                for _ in 0..<abs(batch) {
                    guard self.isCurrent(token) else { success = false; break }
                    guard ResolveTimelineMenuAccess.stepFrame(reverse:reverse,processIdentifier:processIdentifier,canContinue:{ self.isCurrent(token) }) else { success = false; break }
                    Thread.sleep(forTimeInterval:0.06)
                }
            }
            DispatchQueue.main.async {
                guard ResolveJogInFlightPolicy.shouldRelease(activeGeneration:self.drainingGeneration,completedGeneration:token) else { return }
                self.drainingGeneration = nil
                guard self.generationMatches(token) else { return }
                if !success || !AppSettings.touchBarEnabled {
                    self.setStatus(AppSettings.touchBarEnabled ? "Timeline unavailable" : "Touch Bar Off")
                    self.ready = false
                    self.pendingFrames = 0
                    self.accumulator.reset()
                    self.endSessionState()
                }
                self.drain(token:token,processIdentifier:processIdentifier)
            }
        }
    }

    private func endDrag() {
        endSessionState()
        pendingFrames = 0
        ready = false
        drainingGeneration = nil
        accumulator.reset()
        setStatus("Edit timeline only")
    }

    private func endSessionState() {
        stateLock.lock(); dragging = false; generation &+= 1; stateLock.unlock()
    }

    private var isDraggingNow: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return dragging
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        AppSettings.customResolveInteractionAllowed && generationMatches(token)
    }

    private func generationMatches(_ token: UInt64) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return ResolveDragGenerationPolicy.shouldContinue(dragging:dragging,currentGeneration:generation,capturedGeneration:token)
    }

    private func setStatus(_ status: String) {
        jogView.status = status
        jogView.setAccessibilityLabel("DaVinci Resolve relative timeline jog")
        jogView.setAccessibilityValue(status)
        jogView.setAccessibilityHelp("Edit page only. Drag horizontally to step frames. This is relative movement, not an absolute timeline position.")
        jogView.needsDisplay = true
    }

    private func updateAccessibility() { setStatus("Edit timeline only") }
}
