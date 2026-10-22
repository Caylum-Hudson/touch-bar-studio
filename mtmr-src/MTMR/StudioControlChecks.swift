import Cocoa
import ApplicationServices

struct ResolvePageCheckboxSnapshot {
    let role: String
    let label: String
    let selected: Bool
}

enum ResolvePageDetection {
    static let labels: [String: String] = [
        "media":"Media", "photo":"Photo", "cut":"Cut", "edit":"Edit",
        "fusion":"Fusion", "color":"Color", "fairlight":"Fairlight", "deliver":"Deliver"
    ]

    static func selectedPage(in snapshots: [ResolvePageCheckboxSnapshot]) -> String? {
        let recognized = snapshots.filter { snapshot in
            snapshot.role == "AXCheckBox" && labels.values.contains(snapshot.label)
        }
        guard recognized.count >= 3 else { return nil }
        let selected = recognized.filter(\.selected)
        guard selected.count == 1 else { return nil }
        return labels.first { $0.value == selected[0].label }?.key
    }

    static func shouldResetManualOverride(previousProcess: pid_t?, currentProcess: pid_t) -> Bool {
        previousProcess != nil && previousProcess != currentProcess
    }

    static func detect(processIdentifier: pid_t) -> (page: String?, status: String) {
        guard AXIsProcessTrusted() else { return (nil,"accessibility-required") }
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application,0.01)
        guard let mainWindow = axElement(application,kAXMainWindowAttribute),
              let focusedWindow = axElement(application,kAXFocusedWindowAttribute),
              CFEqual(mainWindow,focusedWindow),
              axString(mainWindow,kAXRoleAttribute) == kAXWindowRole,
              axString(mainWindow,kAXSubroleAttribute) == kAXStandardWindowSubrole,
              let children = axArray(mainWindow,kAXChildrenAttribute) else {
            return (nil,"window-unavailable")
        }
        let snapshots = children.prefix(64).compactMap { child -> ResolvePageCheckboxSnapshot? in
            guard axString(child,kAXRoleAttribute) == kAXCheckBoxRole,
                  let label = axString(child,kAXDescriptionAttribute) ?? axString(child,kAXTitleAttribute),
                  labels.values.contains(label),
                  let value = axValue(child,kAXValueAttribute) as? NSNumber else { return nil }
            return ResolvePageCheckboxSnapshot(role:kAXCheckBoxRole,label:label,selected:value.boolValue)
        }
        guard snapshots.filter({ $0.role == kAXCheckBoxRole }).count >= 3 else { return (nil,"page-unknown") }
        guard let page = selectedPage(in:snapshots) else { return (nil,"page-ambiguous") }
        return (page,"detected")
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,attribute as CFString,&value) == .success else { return nil }
        return value
    }
    private static func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value=axValue(element,attribute) else { return nil }
        return value as! AXUIElement
    }
    private static func axArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        axValue(element,attribute) as? [AXUIElement]
    }
    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        axValue(element,attribute) as? String
    }
}

enum StudioFocusRefreshPolicy {
    static func signature(profileIdentifier: String, items: [[String: Any]], bundleIdentifier: String?, blacklisted: Bool = false, selectionContext: String? = nil) -> String? {
        let visibleItems = filterVisibleItems(items, bundleIdentifier: bundleIdentifier)
        guard let data = try? JSONSerialization.data(withJSONObject: visibleItems, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return profileIdentifier + "\nblacklisted:\(blacklisted)\ncontext:\(selectionContext ?? "")\n" + json
    }

    private static func filterVisibleItems(_ items: [[String: Any]], bundleIdentifier: String?) -> [[String: Any]] {
        items.compactMap { source in
            if let pattern = source["matchAppId"] as? String {
                guard let bundleIdentifier else { return nil }
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
                let range = NSRange(location: 0, length: bundleIdentifier.count)
                guard regex.firstMatch(in: bundleIdentifier, range: range) != nil else { return nil }
            }

            var item = source
            if let children = source["items"] as? [[String: Any]] {
                item["items"] = filterVisibleItems(children, bundleIdentifier: bundleIdentifier)
            }
            return item
        }
    }

    static func shouldRefresh(previous: String?, next: String?) -> Bool {
        guard let previous, let next else { return true }
        return previous != next
    }
}

/// Read-only runtime checks: decode defaults and render local status controls without sending actions.
enum StudioControlChecks {
    static func runFocusRefreshPolicyChecks() {
        let pageSnapshots = [
            ResolvePageCheckboxSnapshot(role:"AXCheckBox",label:"Media",selected:false),
            ResolvePageCheckboxSnapshot(role:"AXCheckBox",label:"Edit",selected:true),
            ResolvePageCheckboxSnapshot(role:"AXCheckBox",label:"Color",selected:false),
            ResolvePageCheckboxSnapshot(role:"AXCheckBox",label:"Timeline",selected:true)
        ]
        precondition(ResolvePageDetection.selectedPage(in:pageSnapshots)=="edit", "Resolve detection should use recognized sibling page controls and ignore nested/non-page checkboxes")
        precondition(ResolvePageDetection.selectedPage(in:Array(pageSnapshots.prefix(2)))==nil, "A single or incomplete page control set must not be treated as detection")
        var ambiguousPages=pageSnapshots
        ambiguousPages[2]=ResolvePageCheckboxSnapshot(role:"AXCheckBox",label:"Color",selected:true)
        precondition(ResolvePageDetection.selectedPage(in:ambiguousPages)==nil, "Multiple selected page controls must fall back as ambiguous")
        let selectedModes=StudioFocusRefreshPolicy.signature(profileIdentifier:"resolve",items:[],bundleIdentifier:"com.blackmagic-design.DaVinciResolve",selectionContext:"edit|automatic")
        let manualSamePage=StudioFocusRefreshPolicy.signature(profileIdentifier:"resolve",items:[],bundleIdentifier:"com.blackmagic-design.DaVinciResolve",selectionContext:"edit|manual")
        precondition(StudioFocusRefreshPolicy.shouldRefresh(previous:selectedModes,next:manualSamePage), "Changing Auto/Manual mode on the same page must rebuild the picker state")
        precondition(!ResolvePageDetection.shouldResetManualOverride(previousProcess:nil,currentProcess:101), "A manual page chosen in Studio should survive the first Resolve activation")
        precondition(!ResolvePageDetection.shouldResetManualOverride(previousProcess:101,currentProcess:101), "Changing frontmost apps must not clear the Resolve process override")
        precondition(ResolvePageDetection.shouldResetManualOverride(previousProcess:101,currentProcess:202), "Launching a different Resolve process should clear the old page override")
        let ordinaryAppAuto=StudioFocusRefreshPolicy.signature(profileIdentifier:"default",items:[],bundleIdentifier:"com.example.editor",selectionContext:nil)
        let ordinaryAppManual=StudioFocusRefreshPolicy.signature(profileIdentifier:"default",items:[],bundleIdentifier:"com.example.editor",selectionContext:nil)
        precondition(ordinaryAppAuto == ordinaryAppManual, "Resolve page mode changes must not alter other apps' focus signature")
        let flags=GenericKeyPress.eventFlags(for:["option","shift"])
        precondition(flags.contains(.maskAlternate) && flags.contains(.maskShift) && !flags.contains(.maskCommand), "Shortcut modifiers should be combined as simultaneous event flags")
        let controller=TouchBarController.shared
        let oldOverride=controller.resolvePageOverride
        controller.resolvePageOverride="fairlight"
        let manualPicker=controller.resolvePagePicker(currentPage:"fairlight")
        guard case let .group(items:pageChoices)=manualPicker.type,
              case let .title(manualTitle)?=manualPicker.additionalParameters[.title] else { fatalError("Resolve page picker definition is missing") }
        precondition(manualPicker.isStudioResolvePagePicker, "The generated Manual selector should carry the internal picker marker")
        precondition(manualTitle=="Manual", "Touch Bar page picker title should stay compact while mode remains clear")
        let scale:CGFloat=760/StudioLayout.width
        let manualWidth=(manualTitle as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:15)]).width
        let manualFrame=controller.preciseFrames([manualPicker])[0]
        precondition((manualWidth+12)*scale <= manualFrame.width*scale, "Manual picker title should fit at a 760-unit Touch Bar width")
        let fairlightChoice=pageChoices.first { if case let .staticButton(title)=$0.type { return title=="✓ Fairlight" }; return false }
        guard let fairlightChoice,
              case let .width(choiceWidth)?=fairlightChoice.additionalParameters[.width],
              case let .staticButton(fairlightTitle)=fairlightChoice.type else { fatalError("Selected Fairlight option is missing") }
        let fairlightWidth=(fairlightTitle as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:15)]).width
        precondition((fairlightWidth+12)*scale <= choiceWidth*scale, "Full page option names should fit the Touch Bar picker at 760 units")
        controller.resolvePageOverride=nil
        let autoPicker=controller.resolvePagePicker(currentPage:"edit")
        if case let .title(autoTitle)?=autoPicker.additionalParameters[.title] { precondition(autoTitle=="Auto", "Automatic mode should have a compact, clear picker title") } else { fatalError("Automatic picker title is missing") }
        precondition(autoPicker.isStudioResolvePagePicker, "The generated Auto selector should carry the internal picker marker")

        for title in ["Auto", "Manual"] {
            let userGroup=BarItemDefinition(
                type:.group(items:[]),actions:[],action:.none,legacyLongAction:.none,
                additionalParameters:[.align:.align(.left),.width:.width(64),.title:.title(title),.studioPosition:.studioPosition(200)]
            )
            let neighbor=BarItemDefinition(
                type:.staticButton(title:"Neighbor"),actions:[],action:.none,legacyLongAction:.none,
                additionalParameters:[.align:.align(.left),.width:.width(64),.studioPosition:.studioPosition(300)]
            )
            precondition(!userGroup.isStudioResolvePagePicker, "A user group titled \(title) must not be marked as the generated picker")
            let frames=controller.preciseFrames([userGroup,neighbor])
            precondition(frames[0].minX==200 && frames[0].width==64 && frames[1].minX==300,
                         "A precise layout beginning with a user group titled \(title) must preserve its saved positions")
        }
        controller.resolvePageOverride=oldOverride

        let base: [[String: Any]] = [["type": "staticButton", "title": "Default"]]
        let same = StudioFocusRefreshPolicy.signature(profileIdentifier: "default", items: base, bundleIdentifier: "com.example.one")
        let sameForAnotherApp = StudioFocusRefreshPolicy.signature(profileIdentifier: "default", items: base, bundleIdentifier: "com.example.two")
        precondition(!StudioFocusRefreshPolicy.shouldRefresh(previous: same, next: sameForAnotherApp),
                     "Focus changes with the same effective default profile should preserve the current bar state")

        let changed = StudioFocusRefreshPolicy.signature(profileIdentifier: "work", items: base, bundleIdentifier: "com.example.one")
        precondition(StudioFocusRefreshPolicy.shouldRefresh(previous: same, next: changed),
                     "Switching to another selected profile should refresh the bar")
        let changedLayout = StudioFocusRefreshPolicy.signature(profileIdentifier: "default", items: [["type": "staticButton", "title": "Default", "studioPosition": 120]], bundleIdentifier: "com.example.one")
        precondition(StudioFocusRefreshPolicy.shouldRefresh(previous: same, next: changedLayout),
                     "A saved layout change should refresh the bar")

        let matched: [[String: Any]] = [
            ["type": "staticButton", "title": "Common"],
            ["type": "staticButton", "title": "Mail", "matchAppId": "com\\.example\\.mail"]
        ]
        let mail = StudioFocusRefreshPolicy.signature(profileIdentifier: "default", items: matched, bundleIdentifier: "com.example.mail")
        let editor = StudioFocusRefreshPolicy.signature(profileIdentifier: "default", items: matched, bundleIdentifier: "com.example.editor")
        let noFrontmostApp = StudioFocusRefreshPolicy.signature(profileIdentifier: "default", items: matched, bundleIdentifier: nil)
        precondition(StudioFocusRefreshPolicy.shouldRefresh(previous: mail, next: editor),
                     "A matchAppId visibility change should refresh the bar")
        precondition(editor == noFrontmostApp,
                     "App-specific controls should stay hidden when no frontmost app ID is available")
        precondition(!StudioFocusRefreshPolicy.shouldRefresh(previous: mail, next: mail),
                     "An unchanged effective configuration should retain navigation and expanded-slider state")

        let nested: [[String: Any]] = [[
            "type": "group", "title": "Tools", "items": [
                ["type": "staticButton", "title": "Common"],
                ["type": "staticButton", "title": "Mail", "matchAppId": "com\\.example\\.mail"]
            ]
        ]]
        let nestedMail = StudioFocusRefreshPolicy.signature(profileIdentifier: "default", items: nested, bundleIdentifier: "com.example.mail")
        let nestedEditor = StudioFocusRefreshPolicy.signature(profileIdentifier: "default", items: nested, bundleIdentifier: "com.example.editor")
        precondition(StudioFocusRefreshPolicy.shouldRefresh(previous: nestedMail, next: nestedEditor),
                     "A nested matchAppId visibility change should refresh an open group submenu")

        let blocked = StudioFocusRefreshPolicy.signature(profileIdentifier: "default", items: base, bundleIdentifier: "com.example.one", blacklisted: true)
        precondition(StudioFocusRefreshPolicy.shouldRefresh(previous: same, next: blocked),
                     "Entering a blacklisted app should refresh so the active bar is dismissed")
        precondition(StudioFocusRefreshPolicy.shouldRefresh(previous: blocked, next: same),
                     "Returning to an allowed app should refresh and restore the active bar")
        print("PASS: focus refresh policy handles identical profiles, profile and layout changes, nested matchAppId visibility, and blacklist transitions.")
    }

    static func runDockAutoResizeChecks() {
        let data = "[{\"type\":\"dock\",\"autoResize\":true,\"width\":200,\"studioPosition\":465},{\"type\":\"staticButton\",\"title\":\"Next\",\"width\":64,\"studioPosition\":700}]".data(using: .utf8)!
        let definitions = data.barItemDefinitions()!
        let natural = StudioLayout.frames(definitions, preferredContentWidths: [0: 164])
        precondition(natural[0].minX == 465 && natural[0].width == 164 && natural[1].minX == 700,
                     "A naturally-sized Dock should keep its saved position and leave the following control in place")

        let shrunk = StudioLayout.frames(definitions, preferredContentWidths: [0: 400])
        precondition(shrunk[0].width == 231 && shrunk[1].minX == 700,
                     "An oversized Dock should shrink to the space before the next control")

        let empty = StudioLayout.frames(definitions, preferredContentWidths: [0: 0])
        precondition(empty[0].width == 0 && empty[1].minX == 700,
                     "An empty auto-sized Dock should collapse instead of using the saved width")

        let tightData = "[{\"type\":\"dock\",\"autoResize\":true,\"width\":200,\"studioPosition\":465},{\"type\":\"staticButton\",\"title\":\"Next\",\"width\":64,\"studioPosition\":469}]".data(using: .utf8)!
        let tightDefinitions = tightData.barItemDefinitions()!
        let noRoom = StudioLayout.frames(tightDefinitions, preferredContentWidths: [0: 164])
        precondition(noRoom[0].width == 0 && noRoom[1].minX == 469,
                     "A Dock with no available space should take zero width without overlapping its neighbor")
        let edgeData = "[{\"type\":\"dock\",\"autoResize\":true,\"width\":200,\"studioPosition\":1000}]".data(using: .utf8)!
        let edgeFrames = StudioLayout.frames(edgeData.barItemDefinitions()!, preferredContentWidths: [0: 164])
        precondition(edgeFrames[0].minX == 1000 && edgeFrames[0].width == 85,
                     "A Dock near the bar edge should retain its saved position and fit the remaining width")

        _ = NSApplication.shared
        let dockItems = [
            DockBarItem(DockItem(bundleIdentifier: "test.dock.one", icon: NSImage(size: NSSize(width: 32, height: 32)))),
            DockBarItem(DockItem(bundleIdentifier: "test.dock.two", icon: NSImage(size: NSSize(width: 32, height: 32))))
        ]
        let dockStack = NSStackView(views: dockItems.compactMap { $0.view })
        dockStack.orientation = .horizontal
        dockStack.spacing = 1
        dockItems.forEach { $0.setDisplayIconSize(32) }
        dockStack.layoutSubtreeIfNeeded()
        precondition(dockStack.fittingSize.width <= 65.01,
                     "Explicit Dock button widths should match the 32-point natural icon stack")
        let shrinkScale = 31 / DockAppSnapshotSource.preferredWidth(appCount: 2)
        dockStack.spacing = shrinkScale
        dockItems.forEach { $0.setDisplayIconSize(32 * shrinkScale) }
        dockStack.layoutSubtreeIfNeeded()
        precondition(dockStack.fittingSize.width <= 31.01,
                     "The actual AppKit Dock stack should fit inside the proportionally-shrunk allocation")

        var currentPreferredWidth: CGFloat = 164
        let positioned = StudioPositionedView(
            views: [NSView(frame: .zero), NSView(frame: .zero)],
            frames: natural,
            frameProvider: { _ in StudioLayout.frames(definitions, preferredContentWidths: [0: currentPreferredWidth]) }
        )
        positioned.frame = NSRect(x: 0, y: 0, width: StudioLayout.width, height: 30)
        let identity = ObjectIdentifier(positioned)
        positioned.layout()
        precondition(positioned.subviews[0].frame.width == 164)
        currentPreferredWidth = 65 // two Dock icons rather than five
        positioned.layout()
        precondition(ObjectIdentifier(positioned) == identity && positioned.subviews[0].frame.width == 65 && positioned.subviews[1].frame.minX == 700,
                     "A changed Dock item count should relayout within the existing positioned view")
        print("PASS: Dock natural width, actual AppKit stack fit at natural and shrunk sizes, neighbor-constrained shrink, empty/no-room cases, and count-change relayout without replacing the positioned view.")
    }

    static func runDockPreviewCacheChecks() {
        _ = NSApplication.shared
        let apps = [
            DockItem(bundleIdentifier: "test.preview.one", name: "One", icon: NSImage(size: NSSize(width: 32, height: 32)), running: true),
            DockItem(bundleIdentifier: "test.preview.two", name: "Two", icon: NSImage(size: NSSize(width: 32, height: 32)), running: false)
        ]
        let cache = DockPreviewSnapshotCache(snapshotProvider: { _, _ in DockAppsSnapshot(applications: apps) })
        let first = cache.response(filterPattern: nil, sinceRevision: nil, persistentIdentifiers: [])
        let firstApps = first["apps"] as? [[String: Any]] ?? []
        let firstRevision = first["revision"] as? String ?? ""
        precondition(first["success"] as? Bool == true && first["unchanged"] as? Bool == false && firstApps.count == 2,
                     "Dock preview should return the deterministic app snapshot")
        precondition((first["preferredWidth"] as? CGFloat) == 65 && (first["iconSize"] as? CGFloat) == 32,
                     "Dock preview width should match two 32-point icons and one 1-point gap")
        precondition(firstApps[0]["bundleId"] as? String == "test.preview.one" && firstApps[0]["name"] as? String == "One" &&
                     firstApps[0]["running"] as? Bool == true && (firstApps[0]["iconData"] as? String)?.hasPrefix("data:image/png;base64,") == true,
                     "Dock preview should expose bundle ID, name, running state, and a PNG data URL")

        let unchanged = cache.response(filterPattern: nil, sinceRevision: firstRevision, persistentIdentifiers: [])
        precondition(unchanged["unchanged"] as? Bool == true && unchanged["apps"] == nil,
                     "An unchanged Dock preview revision should avoid retransmitting icon data")
        let changed = cache.response(filterPattern: "Two", sinceRevision: firstRevision, persistentIdentifiers: [])
        precondition(changed["unchanged"] as? Bool == false && (changed["revision"] as? String) != firstRevision,
                     "A Dock filter change should create a fresh preview revision")
        print("PASS: Dock preview snapshot fields, PNG icon data, natural width, revision updates, and unchanged-response caching.")
    }

    static func runStudioContentWidthChecks() {
        _ = NSApplication.shared
        let scale: CGFloat = 760 / StudioLayout.width
        let automaticCPU = CustomButtonTouchBarItem(identifier: .init("test.studio.automaticCPU"), title: "100%")
        automaticCPU.image = NSImage(size: NSSize(width: 20, height: 20))
        let widthConfig: CanSetWidth = automaticCPU
        widthConfig.setWidth(value: 64)
        guard let automaticWidthConstraint = automaticCPU.view.constraints.first(where: { $0.firstAttribute == .width }) else {
            preconditionFailure("Automatic custom-button layout should retain its explicit width constraint")
        }
        automaticCPU.title = "100%"
        precondition(automaticWidthConstraint.constant >= automaticCPU.studioNaturalContentWidth,
                     "Automatic layouts should grow their existing saved-width constraint when live button content grows")

        let date = CustomButtonTouchBarItem(identifier: .init("test.studio.date"), title: "")
        date.attributedTitle = "Wednesday, October 20, 2026".defaultTouchbarAttributedString
        date.setWidth(value: 64)

        let cpu = CustomButtonTouchBarItem(identifier: .init("test.studio.cpu"), title: "100%")
        cpu.image = NSImage(size: NSSize(width: 20, height: 20))
        cpu.setWidth(value: 64)

        let data = "[{\"type\":\"staticButton\",\"title\":\"Date\",\"width\":64,\"studioPosition\":11},{\"type\":\"staticButton\",\"title\":\"CPU\",\"width\":64,\"studioPosition\":201},{\"type\":\"dock\",\"width\":200,\"studioPosition\":520}]".data(using: .utf8)!
        let definitions = data.barItemDefinitions()!
        var positioned: StudioPositionedView!
        positioned = StudioPositionedView(
            views: [date.view, cpu.view, NSView(frame: .zero)],
            frames: StudioLayout.frames(definitions),
            frameProvider: { widths in StudioLayout.frames(definitions, preferredContentWidths: widths) }
        )
        positioned.frame = NSRect(x: 0, y: 0, width: 760, height: 30)
        positioned.attachContentWidthItem(date, at: 0)
        positioned.attachContentWidthItem(cpu, at: 1)
        positioned.layoutSubtreeIfNeeded()

        let originalIdentity = ObjectIdentifier(positioned)
        let dateButton = date.view
        let cpuButton = cpu.view
        precondition(dateButton.frame.minX == 11 * scale && cpuButton.frame.minX == 201 * scale,
                     "Content-based sizing should preserve saved Date and CPU positions at a narrow bar width")
        precondition(dateButton.fittingSize.width <= dateButton.frame.width + 0.25 &&
                     cpuButton.fittingSize.width <= cpuButton.frame.width + 0.25,
                     "Actual AppKit Date and CPU buttons should fit their allocated frames at a scaled canvas width")
        precondition(dateButton.frame.width > 64 * scale && cpuButton.frame.width > 64 * scale,
                     "Long Date and whole-number CPU usage labels should override stale 64-point saved widths transiently")

        date.title = "Wednesday, September 30, 2026"
        positioned.layoutSubtreeIfNeeded()
        precondition(ObjectIdentifier(positioned) == originalIdentity && dateButton.fittingSize.width <= dateButton.frame.width + 0.25,
                     "A live text-width change should relayout the existing positioned view and keep the button content visible")
        print("PASS: actual AppKit Date and CPU buttons fit at narrow canvas scale, keep saved X positions, and update transiently without rebuilding the positioned view.")
    }

    static func runNativeSliderChecks() {
        let selected = BrightnessDisplaySelection.builtInDisplay(from: [101, 202, 303]) { $0 == 202 }
        precondition(selected == 202, "Brightness selection should choose the active built-in display")
        precondition(BrightnessDisplaySelection.builtInDisplay(from: [101, 303]) { _ in false } == nil,
                     "Brightness selection should report no built-in display when none is present")

        _ = NSApplication.shared
        let fakeSlider = NSSlider(frame: .zero)
        var backCount = 0
        let item = ExpandedNativeSliderTouchBarItem(
            identifier: .init("test.expandedSlider"),
            slider: fakeSlider,
            minimumSymbol: "sun.min.fill",
            maximumSymbol: "sun.max.fill",
            onBack: { backCount += 1 }
        )
        item.view.layoutSubtreeIfNeeded()
        precondition(item.sliderRow.arrangedSubviews.count == 3,
                     "Expanded slider should contain minimum endpoint, slider, and maximum endpoint")
        precondition(item.sliderRow.arrangedSubviews[0] is NSImageView &&
                     item.sliderRow.arrangedSubviews[1] === fakeSlider &&
                     item.sliderRow.arrangedSubviews[2] is NSImageView,
                     "Expanded slider endpoints should flank the native slider")
        precondition(abs(item.sliderRow.frame.midX - StudioLayout.width / 2) < 1,
                     "Expanded slider should be centered in the full-width Touch Bar item")
        precondition(item.backButton.frame.minX >= 11,
                     "Expanded slider Back button should remain at the leading edge")
        item.backButton.performClick(nil)
        precondition(backCount == 1, "Expanded slider Back button should invoke its callback once")
        print("PASS: built-in display selection, no-display handling, centered slider endpoints and Back callback.")
    }

    static func run(path: String) throws {
        _ = NSApplication.shared
        TouchBarController.registerNavigationControls(dismiss:{},back:{})
        let data = try Data(contentsOf:URL(fileURLWithPath:path))
        let fixtures = try JSONSerialization.jsonObject(with:data) as! [[String:Any]]
        var activeCount = 0
        let disabled: Set<String> = ["appleScriptTitledButton","shellScriptTitledButton","memoryButton","activeAppButton","swipe"]
        for fixture in fixtures {
            let key = fixture["key"] as! String
            let items = fixture["items"] as! [[String:Any]]
            let safe = StudioStore.shared.safeItems(items)
            precondition(safe.isEmpty == disabled.contains(key),"Unexpected filtering: \(key)")
            if safe.isEmpty { continue }
            let encoded = try JSONSerialization.data(withJSONObject:safe)
            let definitions = encoded.barItemDefinitions()
            precondition(definitions?.count == 1,"Could not decode \(key)")
            if case let .staticButton(title) = definitions![0].type { precondition(title != "unknown","Unknown control: \(key)") }
            activeCount += 1
        }
        precondition(Data("[invalid".utf8).barItemDefinitions() == nil)
        precondition(Data([0xff,0xfe]).barItemDefinitions() == nil)
        let custom = Data("[{\"type\":\"volumeUp\",\"title\":\"Louder\",\"align\":\"right\"}]".utf8).barItemDefinitions()![0]
        precondition(custom.align == .right)
        print("PASS: \(fixtures.count) palette defaults audited; \(activeCount) retained controls decode, 5 export-only controls are filtered.")
        guard CommandLine.arguments.contains("--include-widgets") else { return }
        _ = NSApplication.shared
        let time = TimeTouchBarItem(identifier:.init("test.time"),formatTemplate:"HH:mm")
        precondition(time.title.count == 5 && time.title.contains(":"))
        let battery = BatteryBarItem(identifier:.init("test.battery"))
        precondition(!battery.title.isEmpty)
        let timer = PomodoroBarItem(identifier:.init("test.timer"),workTime:1500,restTime:300)
        precondition(timer.title == "Focus" && timer.image != nil)
        let cpu = CPUBarItem(identifier:.init("test.cpu"),refreshInterval:60)
        RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        precondition(cpu.title.contains("%"))
        runSystemMetricsChecks()
        let board = BoardTemperatureBarItem(identifier:.init("test.board"))
        precondition(board.title == "Board —" && board.image != nil)
        precondition(SystemMetrics.monitorSubscriberCount == 0, "Unavailable board-only item must not start hardware sampling")
        let ram = RAMUsageBarItem(identifier:.init("test.ram"))
        let gpu = GPUUsageBarItem(identifier:.init("test.gpu"))
        let temperature = CPUTemperatureBarItem(identifier:.init("test.cpu-temperature"))
        precondition(SystemMetrics.monitorSubscriberCount == 3, "RAM, GPU, and CPU temperature items should share one active sampler")
        precondition(SystemMetrics.monitorSubscriberCount(for: .ram) == 1 && SystemMetrics.monitorSubscriberCount(for: .gpu) == 1 && SystemMetrics.monitorSubscriberCount(for: .cpuTemperature) == 1)
        RunLoop.current.run(until:Date().addingTimeInterval(2.2))
        precondition(ram.title == "—" || ram.title.range(of: #"^(100|[0-9]{1,2})%$"#, options: .regularExpression) != nil, "RAM widget should show a percentage without a text prefix")
        precondition(gpu.title == "—" || gpu.title.range(of: #"^(100|[0-9]{1,2})%$"#, options: .regularExpression) != nil, "GPU widget must show a bounded percentage or unavailable without a prefix")
        precondition(temperature.title == "—" || temperature.title.range(of: #"^(130|[0-9]{1,2})°C$"#, options: .regularExpression) != nil, "CPU temperature must show a bounded Tp/Te reading or unavailable without a prefix")
        precondition(board.title == "Board —", "No unidentified temperature sensor may be presented as motherboard temperature")
        precondition(ram.studioNaturalContentWidth > 0 && gpu.studioNaturalContentWidth > 0 && temperature.studioNaturalContentWidth > 0 && board.studioNaturalContentWidth > 0)
        print("SYSTEM METRIC SELF-TEST: RAM \(ram.title), GPU \(gpu.title), CPU temperature \(temperature.title), \(board.title)")
        let slider = VolumeViewController(identifier:.init("test.volume"))
        precondition((0...100).contains(slider.sliderItem.doubleValue))
        print("PASS: RAM, GPU, and CPU temperature widgets read local metrics through the shared sampler; board sensor absence stays explicit; metric format and live widths pass.")
        print("PASS: clock, battery, CPU, focus timer and volume slider initialize with local data; malformed input returns an error without crashing.")
        print("NOT TESTED: physical taps, keyboard delivery, hardware changes, external services, Automation and private system toggles.")
    }

    private static func runSystemMetricsChecks() {
        precondition(SystemMetrics.cpuUsageLabel(57.3) == "57%")
        precondition(SystemMetrics.cpuUsageLabel(57.5) == "58%")
        precondition(SystemMetrics.cpuUsageLabel(99.6) == "100%")
        precondition(SystemMetrics.cpuUsageLabel(nil) == "—")
        precondition(SystemMetrics.cpuUsageLabel(.nan) == "—" && SystemMetrics.cpuUsageLabel(.infinity) == "—")
        precondition(SystemMetrics.cpuUsageLabel(-1) == "—" && SystemMetrics.cpuUsageLabel(101) == "—")
        precondition(SystemMetrics.ramPercent(used: nil, total: 100) == nil)
        precondition(SystemMetrics.ramPercent(used: 0, total: 100) == 0)
        precondition(SystemMetrics.ramPercent(used: 1, total: 4) == 25)
        precondition(SystemMetrics.ramPercent(used: 200, total: 100) == 100)
        precondition(SystemMetrics.ramPercent(used: 1, total: 0) == nil)
        precondition(SystemMetrics.gpuPercent(nil) == nil)
        precondition(SystemMetrics.gpuPercent(.nan) == nil && SystemMetrics.gpuPercent(.infinity) == nil)
        precondition(SystemMetrics.gpuPercent(-1) == nil && SystemMetrics.gpuPercent(101) == nil)
        precondition(SystemMetrics.gpuPercent(0) == 0 && SystemMetrics.gpuPercent(100) == 100)
        precondition(SystemMetrics.unsupportedBoardLabel == "Board —")
        precondition(SystemMetrics.cpuTemperatureLabel(nil) == "CPU —")
        precondition(SystemMetrics.cpuTemperatureLabel(.nan) == "CPU —" && SystemMetrics.cpuTemperatureLabel(.infinity) == "CPU —")
        precondition(SystemMetrics.cpuTemperatureLabel(0) == "CPU —", "uninitialized zero must remain unavailable")
        precondition(SystemMetrics.cpuTemperatureLabel(-1) == "CPU —" && SystemMetrics.cpuTemperatureLabel(131) == "CPU —")
        precondition(SystemMetrics.cpuTemperatureLabel(56.7) == "CPU 57°C")
        precondition(SystemMetrics.ramUsedBytes(internalPages: 100, purgeablePages: 20, wiredPages: 30, compressedPages: 10, pageSize: 4096) == 491_520)
        precondition(SystemMetrics.ramUsedBytes(internalPages: 10, purgeablePages: 11, wiredPages: 0, compressedPages: 0, pageSize: 4096) == nil)
        precondition(SystemMetrics.ramUsedBytes(internalPages: 1, purgeablePages: 0, wiredPages: 0, compressedPages: 0, pageSize: 0) == nil)
        print("PASS: system metric calculations clamp invalid data and show explicit unavailable sensor values.")
    }
}
