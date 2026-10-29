import AppKit
import ApplicationServices

/// A learned position is relative to a freshly resolved HDR panel, never a screen position.
struct ResolveNumericBinding: Codable, Equatable {
    let version: Int
    let zone: String
    let readout: String
    let panelWidth: Double
    let panelHeight: Double
    let anchorX: Double
    let anchorY: Double
    let fingerprint: [String]

    var target: String { "HDR \(zone) \(readout)" }
    var isValid: Bool {
        version == 1 && ["Black","Dark","Shadow","Light","Highlight","Specular","Global"].contains(zone) && ["Exp","Sat"].contains(readout) && fingerprint.count >= 3 && fingerprint.count <= 7 && Set(fingerprint).count == fingerprint.count && fingerprint.contains(zone) && fingerprint.allSatisfy { ["Black","Dark","Shadow","Light","Highlight","Specular","Global"].contains($0) } &&
        [panelWidth,panelHeight,anchorX,anchorY].allSatisfy(\.isFinite) &&
        panelWidth > 10 && panelWidth <= 10000 && panelHeight > 10 && panelHeight <= 10000 && (0...1).contains(anchorX) && (0...1).contains(anchorY)
    }
    func matches(size: CGSize, fingerprint: [String]) -> Bool {
        self.fingerprint == fingerprint && matches(size:size)
    }
    func matches(size:CGSize) -> Bool {
        isValid && abs(Double(size.width) / panelWidth - 1) < 0.025 && abs(Double(size.height) / panelHeight - 1) < 0.025
    }
    static func pagingDirection(from current:[String],to target:[String],seen:[[String]]) -> Int? {
        let order=["Black","Dark","Shadow","Light","Highlight","Specular"]
        func start(_ row:[String]) -> Int? {
            guard row.count == 4, row.last == "Global", let first=row.first, let index=order.firstIndex(of:first), index+3 <= order.count,
                  Array(order[index..<index+3]) == Array(row.prefix(3)) else { return nil }
            return index
        }
        guard seen.count < 6, !seen.contains(current), let currentIndex=start(current), let targetIndex=start(target), current != target else { return nil }
        return currentIndex < targetIndex ? 1 : -1
    }
    static func isHDRPaletteLabel(_ label:String) -> Bool { label.filter { !$0.isWhitespace } == "HDRGrade" }
    static func readoutBeforeEditor(_ text:String) -> String? {
        let regex=try! NSRegularExpression(pattern:#"(Exp|Sat)\s*[-+]?(?:\d+\.\d+|\d+)"#)
        let range=NSRange(text.startIndex..<text.endIndex,in:text)
        guard let match=regex.matches(in:text,range:range).last, let name=Range(match.range(at:1),in:text) else { return nil }
        return String(text[name])
    }
    static func editorReadoutMatches(_ text:String,expected:String) -> Bool {
        readoutBeforeEditor(text) == expected
    }
    static func namedValue(_ readout:String,in text:String) -> Double? {
        guard ["Exp","Sat"].contains(readout), let regex=try? NSRegularExpression(pattern:readout + #"\s*([-+]?(?:\d+\.\d+|\d+))"#) else { return nil }
        let matches=regex.matches(in:text,range:NSRange(text.startIndex..<text.endIndex,in:text))
        guard matches.count == 1, let match=matches.first, let range=Range(match.range(at:1),in:text), let value=Double(text[range]), value.isFinite else { return nil }
        return value
    }
    static func nextValue(current: Double, points: Double, step: Double) -> Double? {
        guard current.isFinite, points.isFinite, step.isFinite, step >= 0.0001, step <= 1 else { return nil }
        let delta = max(-4 * step,min(4 * step,points * step / 12))
        let next = ((current + delta) / step).rounded() * step
        return next.isFinite && abs(next) <= 10000 ? next : nil
    }
}

private final class ResolveNumericNode {
    let element: AXUIElement
    let role: String
    let label: String
    let frame: CGRect
    var children: [ResolveNumericNode] = []
    init(_ element: AXUIElement, role: String, label: String, frame: CGRect) {
        self.element=element; self.role=role; self.label=label; self.frame=frame
    }
    var nodes: [ResolveNumericNode] { [self] + children.flatMap { $0.nodes } }
}

/// Learning, editor activation and edits share one queue and one editor owner.
/// All writes require the live Resolve Color/HDR context again; a failed check closes ownership.
final class ResolveNumericDialReader {
    static let shared = ResolveNumericDialReader()
    private let queue=DispatchQueue(label:"nz.caylum.touchbarstudio.resolve-numeric",qos:.userInitiated)
    private let lock=NSLock()
    private var learnResult: [String:Any] = ["success":true,"state":"idle","id":"","message":""]
    private var learnGeneration=0
    private var learning=false
    private var owner: String?
    private var session: (pid:pid_t,binding:ResolveNumericBinding,value:Double,remainder:Double)?
    private var displays: [String:(String,String)] = [:]
    private var activeGeneration=0
    private var testID:String?
    private var testBefore:Double?
    private var pendingEndGeneration:Int?
    private var pendingMotion:[String:(points:Double,step:Double,generation:Int)] = [:]

    func learnResponse() -> [String:Any] { lock.lock(); defer { lock.unlock() }; return learnResult }
    func startLearning(id:String) {
        queue.async {
            guard AppSettings.customResolveInteractionAllowed else { self.setLearn(["success":false,"state":"error","id":id,"message":"Use the custom Color bar to learn this control."]); return }
            guard self.owner == nil, self.testID == nil else { self.setLearn(["success":false,"state":"error","id":id,"message":"Finish the Touch Bar gesture before learning."]); return }
            self.learnGeneration += 1; self.learning=true
            let generation=self.learnGeneration
            self.setLearn(["success":true,"state":"learning","id":id,"message":"Focus Resolve Color page, open HDR, then double-click the numeric value to bind. No value will be changed."])
            self.pollLearn(id:id,generation:generation,deadline:Date().addingTimeInterval(30))
        }
    }
    func test(id:String,binding:ResolveNumericBinding,step:Double,direction:Int) {
        queue.async {
            guard AppSettings.customResolveInteractionAllowed else { self.setLearn(["success":false,"state":"error","id":id,"message":"Use the custom Color bar to test this control."]); return }
            guard !self.learning, self.owner == nil, self.testID == nil else { self.setLearn(["success":false,"state":"error","id":id,"message":"Finish the current learning or dial gesture first."]); return }
            self.testID=id; self.testBefore=nil
            self.setLearn(["success":true,"state":"testing","id":id,"message":"Testing one configured step in Resolve."])
            self.waitForTestFocus(id:id,binding:binding,step:step,direction:direction,deadline:Date().addingTimeInterval(1.5))
        }
    }
    private func waitForTestFocus(id:String,binding:ResolveNumericBinding,step:Double,direction:Int,deadline:Date) {
        guard testID == id else { return }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.blackmagic-design.DaVinciResolve" {
            begin(id:id,binding:binding)
            queue.asyncAfter(deadline:.now()+0.05) { self.pollTest(id:id,step:step,direction:direction,deadline:Date().addingTimeInterval(8)) }
            return
        }
        guard Date() < deadline else { finishTest(id:id,success:false,message:"Focus Resolve to test this control."); return }
        queue.asyncAfter(deadline:.now()+0.05) { self.waitForTestFocus(id:id,binding:binding,step:step,direction:direction,deadline:deadline) }
    }
    private func pollTest(id:String,step:Double,direction:Int,deadline:Date) {
        guard testID == id else { return }
        if let session=session, owner == id {
            testBefore=session.value
            move(id:id,points:Double(direction)*12,step:step)
            end(id:id)
            return
        }
        guard owner == id, Date() < deadline else { finishTest(id:id,success:false,message:"Could not activate the bound HDR editor. Show its zone and learn again if needed."); return }
        queue.asyncAfter(deadline:.now()+0.05) { self.pollTest(id:id,step:step,direction:direction,deadline:deadline) }
    }
    private func finishTest(id:String,success:Bool,message:String,after:Double? = nil) {
        guard testID == id else { return }
        var result:[String:Any] = ["success":success,"state":success ? "tested" : "error","id":id,"message":message]
        if let before=testBefore { result["before"]=before }
        if let after=after { result["after"]=after }
        testID=nil; testBefore=nil; setLearn(result)
    }
    func cancelLearning() { queue.async { self.learnGeneration += 1; self.learning=false; let id=self.learnResponse()["id"] as? String ?? ""; self.setLearn(["success":true,"state":"idle","id":id,"message":"Learning cancelled."]) } }
    func cancelAllForNativeColor() {
        queue.async {
            self.learnGeneration += 1
            self.learning=false
            if let session=self.session, let editor=self.editor(pid:session.pid,binding:session.binding), NSWorkspace.shared.frontmostApplication?.processIdentifier == session.pid {
                var names:CFArray?; _=AXUIElementCopyActionNames(editor,&names)
                if (names as? [String] ?? []).contains(kAXCancelAction) { _=AXUIElementPerformAction(editor,kAXCancelAction as CFString) }
                else { self.key(53,pid:session.pid) }
            }
            self.clear("Use custom Color bar")
            if let id=self.testID { self.finishTest(id:id,success:false,message:"Use custom Color bar") }
            self.setLearn(["success":false,"state":"error","id":"","message":"Use custom Color bar"])
        }
    }
    private func setLearn(_ result:[String:Any]) { lock.lock(); learnResult=result; lock.unlock() }
    private func setDisplay(_ value:String,_ state:String,id:String? = nil) {
        guard let key=id ?? owner else { return }
        lock.lock(); displays[key]=(value,state); lock.unlock()
    }
    func sample(id:String,bound:Bool) -> (String,String) {
        guard bound else { return ("—","Bind control") }
        guard AppSettings.customResolveInteractionAllowed else { return ("—","Use custom Color bar") }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.blackmagic-design.DaVinciResolve" else { return ("—","Focus Resolve") }
        lock.lock(); defer { lock.unlock() }; return displays[id] ?? ("—","Ready")
    }
    private func pollLearn(id:String,generation:Int,deadline:Date) {
        guard learning, generation == learnGeneration else { return }
        if let context=context(), context.panel.nodes.filter({ $0.role == kAXTextFieldRole && settable($0.element) }).count == 1,
           let focused=element(context.app,kAXFocusedUIElementAttribute),
           let editor=context.panel.nodes.first(where:{ CFEqual($0.element,focused) && $0.role == kAXTextFieldRole }),
           settable(editor.element), let value=number(editor.element), value.isFinite,
           let binding=learnBinding(editor:editor,panel:context.panel) {
            learning=false
            let object=(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(binding))) ?? NSNull()
            setLearn(["success":true,"state":"captured","id":id,"message":"Bound \(binding.target). The editor was left unchanged; finish it normally in Resolve.","binding":object,"target":binding.target])
            return
        }
        guard Date() < deadline else { learning=false; setLearn(["success":false,"state":"error","id":id,"message":"No unambiguous editable HDR value found. Open the intended HDR zone and double-click its numeric value, then learn again."]); return }
        queue.asyncAfter(deadline:.now()+0.2) { self.pollLearn(id:id,generation:generation,deadline:deadline) }
    }
    func begin(id:String,binding:ResolveNumericBinding) {
        queue.async {
            guard !self.learning, self.owner == nil, self.testID == nil || self.testID == id, binding.isValid, AppSettings.touchBarEnabled,
                  let context=self.context(), binding.matches(size:context.panel.frame.size) else { self.setDisplay("—","Show HDR zone",id:id); return }
            guard !self.hasEditor(context.panel) else { self.setDisplay("—","Finish Resolve edit",id:id); return }
            self.activeGeneration += 1; self.pendingEndGeneration=nil; self.owner=id
            self.prepareTarget(id:id,pid:context.pid,binding:binding,generation:self.activeGeneration,seen:[])
        }
    }
    private func hasEditor(_ panel:ResolveNumericNode) -> Bool { panel.nodes.contains { $0.role == kAXTextFieldRole && settable($0.element) } }
    private func prepareTarget(id:String,pid:pid_t,binding:ResolveNumericBinding,generation:Int,seen:[[String]]) {
        guard owner == id, activeGeneration == generation else { return }
        guard let context=context(), context.pid == pid, binding.matches(size:context.panel.frame.size), !hasEditor(context.panel) else { clear("Show HDR zone"); return }
        let row=fingerprint(context.panel)
        if row == binding.fingerprint { activateTarget(id:id,pid:pid,binding:binding,generation:generation,panel:context.panel); return }
        guard let direction=ResolveNumericBinding.pagingDirection(from:row,to:binding.fingerprint,seen:seen),
              let button=navigationButton(direction:direction,panel:context.panel),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, AppSettings.touchBarEnabled else { clear("Show HDR zone"); return }
        setDisplay("—","Finding HDR zone")
        guard click(CGPoint(x:button.frame.midX,y:button.frame.midY),pid:pid) else { clear("Show HDR zone"); return }
        queue.asyncAfter(deadline:.now()+0.08) { self.awaitPage(id:id,pid:pid,binding:binding,generation:generation,previous:row,seen:seen+[row],deadline:Date().addingTimeInterval(0.3)) }
    }
    private func awaitPage(id:String,pid:pid_t,binding:ResolveNumericBinding,generation:Int,previous:[String],seen:[[String]],deadline:Date) {
        guard owner == id, activeGeneration == generation else { return }
        guard let context=context(), context.pid == pid, binding.matches(size:context.panel.frame.size), !hasEditor(context.panel) else { clear("Show HDR zone"); return }
        let row=fingerprint(context.panel)
        if row != previous { prepareTarget(id:id,pid:pid,binding:binding,generation:generation,seen:seen); return }
        guard Date() < deadline else { clear("Show HDR zone"); return }
        queue.asyncAfter(deadline:.now()+0.08) { self.awaitPage(id:id,pid:pid,binding:binding,generation:generation,previous:previous,seen:seen,deadline:deadline) }
    }
    private func navigationButton(direction:Int,panel:ResolveNumericNode) -> ResolveNumericNode? {
        guard panel.children.count >= 2 else { return nil }
        let buttons=Array(panel.children.prefix(2)), zones=zoneNodes(panel)
        guard buttons.allSatisfy({ $0.role == kAXButtonRole }), buttons[0].frame.maxX < buttons[1].frame.minX,
              let headingTop=zones.map({ $0.frame.minY }).min(), buttons.allSatisfy({ button in
                  let frame=button.frame
                  return frame.width >= 4 && frame.width <= 60 && frame.height >= 4 && frame.height <= 50 && panel.frame.contains(frame) && frame.maxY <= headingTop+4
              }) else { return nil }
        let chosen=buttons[direction < 0 ? 0 : 1]
        guard (value(chosen.element,kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { return nil }
        return chosen
    }
    private func activateTarget(id:String,pid:pid_t,binding:ResolveNumericBinding,generation:Int,panel:ResolveNumericNode) {
        let point=CGPoint(x:panel.frame.minX + CGFloat(binding.anchorX)*panel.frame.width,y:panel.frame.minY + CGFloat(binding.anchorY)*panel.frame.height)
        let labels=panel.nodes.filter { $0.role == kAXStaticTextRole && $0.label.range(of:binding.readout) != nil && $0.frame.insetBy(dx:-8,dy:-4).contains(point) }
        guard binding.matches(size:panel.frame.size,fingerprint:fingerprint(panel)), labels.count == 1, zone(at:point,in:panel) == binding.zone,
              owner == id, activeGeneration == generation, AppSettings.touchBarEnabled else { clear("Rebind control"); return }
        guard doubleClick(point,pid:pid) else { clear("Cannot open value"); return }
        awaitEditor(id:id,pid:pid,binding:binding,generation:generation,deadline:Date().addingTimeInterval(0.4))
    }
    private func awaitEditor(id:String,pid:pid_t,binding:ResolveNumericBinding,generation:Int,deadline:Date) {
        guard owner == id, activeGeneration == generation else { return }
        if let resolved=editor(pid:pid,binding:binding), let value=number(resolved) {
            session=(pid,binding,value,0); setDisplay(format(value),"Ready"); if pendingEndGeneration == generation { end(id:id) }; return
        }
        guard Date() < deadline else { clear("Cannot open value"); return }
        queue.asyncAfter(deadline:.now()+0.04) { self.awaitEditor(id:id,pid:pid,binding:binding,generation:generation,deadline:deadline) }
    }
    func move(id:String,points:Double,step:Double) {
        guard points.isFinite, step.isFinite, step >= 0.0001, step <= 1 else { return }
        queue.async {
            guard self.owner == id else { return }
            if var pending=self.pendingMotion[id], pending.generation == self.activeGeneration {
                pending.points=max(-48,min(48,pending.points+points)); self.pendingMotion[id]=pending
            } else {
                let generation=self.activeGeneration
                self.pendingMotion[id]=(max(-48,min(48,points)),step,generation)
                self.queue.asyncAfter(deadline:.now()+0.06) { self.flushMotion(id:id,generation:generation) }
            }
        }
    }
    private func flushMotion(id:String,generation:Int) {
        guard owner == id, activeGeneration == generation, let motion=pendingMotion[id], motion.generation == generation else { return }
        guard let session=session else {
            queue.asyncAfter(deadline:.now()+0.04) { self.flushMotion(id:id,generation:generation) }; return
        }
        pendingMotion.removeValue(forKey:id)
        let points=motion.points, step=motion.step
        guard AppSettings.customResolveInteractionAllowed, let editor=editor(pid:session.pid,binding:session.binding),
              let current=number(editor), let next=ResolveNumericBinding.nextValue(current:current,points:points + session.remainder * 12 / step,step:step) else { clear("Show HDR zone"); return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == session.pid, AppSettings.customResolveInteractionAllowed else { clear("Use custom Color bar"); return }
        guard AXUIElementSetAttributeValue(editor,kAXValueAttribute as CFString,format(next) as CFString) == .success,
              let readback=number(editor), abs(readback-next) < 0.00001 else { clear("Value unavailable"); return }
        let requested=current + session.remainder + max(-4 * step,min(4 * step,points * step / 12))
        self.session=(session.pid,session.binding,readback,requested-next); setDisplay(format(readback),"Ready")
    }
    func end(id:String) {
        queue.async {
            guard self.owner == id else { return }
            guard self.session != nil else { self.pendingEndGeneration=self.activeGeneration; return }
            self.flushMotion(id:id,generation:self.activeGeneration)
            guard self.owner == id, let session=self.session, AppSettings.touchBarEnabled,
                  let editor=self.editor(pid:session.pid,binding:session.binding) else { self.clear("Check HDR layout"); return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == session.pid else { self.clear("Focus Resolve"); return }
            var actionNames:CFArray?
            _=AXUIElementCopyActionNames(editor,&actionNames)
            let actions=actionNames as? [String] ?? []
            if actions.contains(kAXConfirmAction) { _=AXUIElementPerformAction(editor,kAXConfirmAction as CFString) }
            else { self.key(36,pid:session.pid) }
            let expected=session.value, binding=session.binding, pid=session.pid
            self.pendingEndGeneration=nil; self.pendingMotion.removeValue(forKey:id); self.owner=nil; self.session=nil; self.activeGeneration += 1
            let generation=self.activeGeneration
            self.queue.asyncAfter(deadline:.now()+0.1) {
                guard generation == self.activeGeneration else { self.finishTest(id:id,success:false,message:"The control context changed before verification."); return }
                guard let context=self.context(), context.pid == pid, binding.matches(size:context.panel.frame.size,fingerprint:self.fingerprint(context.panel)),
                      let actual=self.staticValue(binding:binding,panel:context.panel), abs(actual-expected) < 0.0001 else { self.setDisplay("—","Check committed value",id:id); self.finishTest(id:id,success:false,message:"Resolve did not confirm the committed value."); return }
                self.setDisplay(self.format(actual),"Ready",id:id)
                self.finishTest(id:id,success:self.testBefore != actual,message:self.testBefore != actual ? "Resolve confirmed the adjustment." : "No value change was confirmed.",after:actual)
            }
        }
    }
    func cancel(id:String) {
        queue.async {
            guard self.owner == id else { return }
            if let session=self.session, AppSettings.touchBarEnabled, let editor=self.editor(pid:session.pid,binding:session.binding), NSWorkspace.shared.frontmostApplication?.processIdentifier == session.pid {
                var names:CFArray?; _=AXUIElementCopyActionNames(editor,&names)
                if (names as? [String] ?? []).contains(kAXCancelAction) { _=AXUIElementPerformAction(editor,kAXCancelAction as CFString) }
                else { self.key(53,pid:session.pid) }
            }
            self.clear("Ready")
        }
    }
    private func clear(_ state:String) { pendingEndGeneration=nil; let id=owner; if let id=id { pendingMotion.removeValue(forKey:id) }; setDisplay("—",state); owner=nil; session=nil; activeGeneration += 1; if let id=id { finishTest(id:id,success:false,message:state) } }

    private func context() -> (app:AXUIElement,pid:pid_t,panel:ResolveNumericNode)? {
        guard AppSettings.customResolveInteractionAllowed, AXIsProcessTrusted(), let running=NSWorkspace.shared.frontmostApplication,
              running.bundleIdentifier == "com.blackmagic-design.DaVinciResolve",
              ResolvePageDetection.detect(processIdentifier:running.processIdentifier).page == "color" else { return nil }
        let app=AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app,0.02)
        guard let window=element(app,kAXMainWindowAttribute), let focused=element(app,kAXFocusedWindowAttribute), CFEqual(window,focused),
              string(window,kAXSubroleAttribute) == kAXStandardWindowSubrole else { return nil }
        var budget=1800
        let deadline=Date().addingTimeInterval(0.5)
        guard let tree=tree(window,depth:0,budget:&budget,deadline:deadline) else { return nil }
        let nodes=tree.nodes
        guard nodes.filter({ ResolveNumericBinding.isHDRPaletteLabel($0.label) && $0.role == kAXCheckBoxRole && (value($0.element,kAXValueAttribute) as? NSNumber)?.boolValue == true }).count == 1 else { return nil }
        let headings=nodes.filter { $0.children.contains { $0.label == "High Dynamic Range - Color Wheels" } }
        guard headings.count == 1, let heading=headings.first else { return nil }
        // The smallest zone container within the visible HDR Wheels palette is the panel.
        let candidates=heading.nodes.filter { node in node.role != kAXWindowRole && node.frame.width > 100 && zoneNodes(node).count >= 3 }
        let leaves=candidates.filter { candidate in !candidate.children.contains { child in candidates.contains { $0 === child } || zoneNodes(child).count >= 3 } }
        guard leaves.count == 1, let panel=leaves.first else { return nil }
        return (app,running.processIdentifier,panel)
    }
    private static let zones=["Black","Dark","Shadow","Light","Highlight","Specular","Global"]
    private func zoneName(_ label:String) -> String? {
        Self.zones.first { label == $0 || (label.hasSuffix($0) && !ResolveColorDialStructure.numericValues(String(label.dropLast($0.count))).isEmpty) }
    }
    private func zoneNodes(_ panel:ResolveNumericNode) -> [ResolveNumericNode] { panel.nodes.filter { $0.role == kAXStaticTextRole && zoneName($0.label) != nil } }
    private func fingerprint(_ panel:ResolveNumericNode) -> [String] {
        zoneNodes(panel).sorted { $0.frame.minX < $1.frame.minX }.compactMap { zoneName($0.label) }
    }
    private func zone(at point:CGPoint,in panel:ResolveNumericNode) -> String? {
        let matches=zoneNodes(panel).filter { $0.frame.minY < point.y }.sorted { abs($0.frame.midX-point.x) < abs($1.frame.midX-point.x) }
        guard let first=matches.first, matches.count == 1 || abs(first.frame.midX-point.x)+10 < abs(matches[1].frame.midX-point.x) else { return nil }
        return zoneName(first.label)
    }
    private func learnBinding(editor:ResolveNumericNode,panel:ResolveNumericNode) -> ResolveNumericBinding? {
        let point=CGPoint(x:editor.frame.midX,y:editor.frame.midY)
        guard panel.frame.contains(point), let zone=zone(at:point,in:panel) else { return nil }
        // Resolve splits its merged static label immediately before the focused editor.
        let parents=panel.nodes.filter { node in node.children.contains { $0 === editor } }
        guard parents.count == 1, let parent=parents.first,
              let index=parent.children.firstIndex(where:{ $0 === editor }), index > 0 else { return nil }
        let label=parent.children[index-1]
        guard label.role == kAXStaticTextRole, let readout=ResolveNumericBinding.readoutBeforeEditor(label.label),
              abs(label.frame.midY-point.y) < max(12,editor.frame.height) else { return nil }
        let binding=ResolveNumericBinding(version:1,zone:zone,readout:readout,panelWidth:Double(panel.frame.width),panelHeight:Double(panel.frame.height),anchorX:Double((point.x-panel.frame.minX)/panel.frame.width),anchorY:Double((point.y-panel.frame.minY)/panel.frame.height),fingerprint:fingerprint(panel))
        return binding.isValid ? binding : nil
    }
    private func editor(pid:pid_t,binding:ResolveNumericBinding) -> AXUIElement? {
        guard let context=context(), context.pid == pid, binding.matches(size:context.panel.frame.size,fingerprint:fingerprint(context.panel)),
              let focused=element(context.app,kAXFocusedUIElementAttribute) else { return nil }
        let matches=context.panel.nodes.filter { $0.role == kAXTextFieldRole && settable($0.element) }
        guard matches.count == 1, let target=matches.first, CFEqual(target.element,focused) else { return nil }
        let parents=context.panel.nodes.filter { node in node.children.contains { $0 === target } }
        guard parents.count == 1, let parent=parents.first,
              let index=parent.children.firstIndex(where:{ $0 === target }), index > 0,
              let marker=parent.children.item(at:index-1), marker.role == kAXStaticTextRole,
              abs(marker.frame.midY-target.frame.midY) < max(12,target.frame.height),
              ResolveNumericBinding.editorReadoutMatches(marker.label,expected:binding.readout),
              zone(at:CGPoint(x:target.frame.midX,y:target.frame.midY),in:context.panel) == binding.zone else { return nil }
        let expected=CGPoint(x:context.panel.frame.minX+CGFloat(binding.anchorX)*context.panel.frame.width,y:context.panel.frame.minY+CGFloat(binding.anchorY)*context.panel.frame.height)
        guard target.frame.insetBy(dx:-3,dy:-3).contains(expected) else { return nil }
        return target.element
    }
    private func staticValue(binding:ResolveNumericBinding,panel:ResolveNumericNode) -> Double? {
        let point=CGPoint(x:panel.frame.minX+CGFloat(binding.anchorX)*panel.frame.width,y:panel.frame.minY+CGFloat(binding.anchorY)*panel.frame.height)
        let matches=panel.nodes.filter { $0.role == kAXStaticTextRole && $0.label.range(of:binding.readout) != nil && $0.frame.insetBy(dx:-8,dy:-4).contains(point) && zone(at:point,in:panel) == binding.zone }
        guard matches.count == 1, let text=matches.first?.label else { return nil }
        return ResolveNumericBinding.namedValue(binding.readout,in:text)
    }
    private func click(_ point:CGPoint,pid:pid_t) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, AppSettings.touchBarEnabled,
              let down=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left),
              let up=CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:point,mouseButton:.left) else { return false }
        down.setIntegerValueField(.mouseEventClickState,value:1); up.setIntegerValueField(.mouseEventClickState,value:1)
        down.postToPid(pid); up.postToPid(pid)
        return true
    }
    private func doubleClick(_ point:CGPoint,pid:pid_t) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        for click in 1...2 {
            guard let down=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left), let up=CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:point,mouseButton:.left) else { return false }
            down.setIntegerValueField(.mouseEventClickState,value:Int64(click)); up.setIntegerValueField(.mouseEventClickState,value:Int64(click))
            down.postToPid(pid); up.postToPid(pid)
        }
        return true
    }
    private func key(_ code:CGKeyCode,pid:pid_t) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let down=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true), let up=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:false) else { return }
        down.postToPid(pid); up.postToPid(pid)
    }
    private func tree(_ element:AXUIElement,depth:Int,budget:inout Int,deadline:Date) -> ResolveNumericNode? {
        guard depth < 16, budget > 0, Date() < deadline else { return nil }; budget -= 1
        let node=ResolveNumericNode(element,role:string(element,kAXRoleAttribute) ?? "",label:string(element,kAXTitleAttribute) ?? string(element,kAXDescriptionAttribute) ?? string(element,kAXValueAttribute) ?? "",frame:frame(element))
        let children=value(element,kAXChildrenAttribute) as? [AXUIElement] ?? []
        guard children.count <= 180 else { return nil }
        for child in children {
            guard let parsed=tree(child,depth:depth+1,budget:&budget,deadline:deadline) else { return nil }
            node.children.append(parsed)
        }
        return node
    }
    private func value(_ element:AXUIElement,_ key:String) -> CFTypeRef? { var result:CFTypeRef?; return AXUIElementCopyAttributeValue(element,key as CFString,&result) == .success ? result : nil }
    private func string(_ element:AXUIElement,_ key:String) -> String? { guard let text=value(element,key) as? String, !text.isEmpty else { return nil }; return text }
    private func element(_ source:AXUIElement,_ key:String) -> AXUIElement? { guard let result=value(source,key), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }; return (result as! AXUIElement) }
    private func number(_ element:AXUIElement) -> Double? { if let number=value(element,kAXValueAttribute) as? NSNumber { return number.doubleValue }; return string(element,kAXValueAttribute).flatMap(Double.init) }
    private func settable(_ element:AXUIElement) -> Bool { var flag=DarwinBoolean(false); return AXUIElementIsAttributeSettable(element,kAXValueAttribute as CFString,&flag) == .success && flag.boolValue }
    private func frame(_ element:AXUIElement) -> CGRect {
        guard let position=value(element,kAXPositionAttribute), let size=value(element,kAXSizeAttribute), CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return .zero }
        var point=CGPoint.zero, dimensions=CGSize.zero
        guard AXValueGetValue(position as! AXValue,.cgPoint,&point), AXValueGetValue(size as! AXValue,.cgSize,&dimensions) else { return .zero }
        return CGRect(origin:point,size:dimensions)
    }
    private func format(_ value:Double) -> String { String(format:"%.4f",locale:Locale(identifier:"en_US_POSIX"),value) }
}

final class ResolveNumericDialTouchBarItem: NSCustomTouchBarItem {
    private let dial=ResolveDialView(frame:NSRect(x:0,y:0,width:110,height:30))
    private let binding:ResolveNumericBinding?
    private let step:Double
    private let controlID:String
    private var timer:Timer?
    init(identifier:NSTouchBarItem.Identifier,title:String,step:Double,binding:ResolveNumericBinding?) {
        self.binding=binding?.isValid == true ? binding : nil; self.step=step; controlID=identifier.rawValue
        super.init(identifier:identifier); view=dial; dial.minimumContentWidth=110; dial.title=title.isEmpty ? "HDR" : title
        dial.onDragStart={ [weak self] in guard let self, let binding=self.binding else { return }; ResolveNumericDialReader.shared.begin(id:self.controlID,binding:binding) }
        dial.onDelta={ [weak self] points in guard let self else { return }; ResolveNumericDialReader.shared.move(id:self.controlID,points:Double(points),step:self.step) }
        dial.onDragEnd={ [weak self] in guard let self else { return }; ResolveNumericDialReader.shared.end(id:self.controlID) }
        dial.onDragCancel={ [weak self] in guard let self else { return }; ResolveNumericDialReader.shared.cancel(id:self.controlID) }
        timer=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in self?.refresh() }; refresh()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func cancelStudioInteraction() { ResolveNumericDialReader.shared.cancel(id:controlID) }
    deinit { timer?.invalidate(); ResolveNumericDialReader.shared.cancel(id:controlID) }
    private func refresh() {
        let sample=ResolveNumericDialReader.shared.sample(id:controlID,bound:binding != nil); dial.valueText=sample.0; dial.status=sample.1; dial.value=0.5
        dial.setAccessibilityLabel(dial.title); dial.setAccessibilityValue(sample.0); dial.setAccessibilityHelp(binding?.target ?? "Learn an HDR numeric control in Studio."); dial.needsDisplay=true
    }
}
