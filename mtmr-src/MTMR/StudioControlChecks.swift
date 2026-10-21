import Cocoa

enum StudioFocusRefreshPolicy {
    static func signature(profileIdentifier: String, items: [[String: Any]], bundleIdentifier: String?, blacklisted: Bool = false) -> String? {
        let visibleItems = filterVisibleItems(items, bundleIdentifier: bundleIdentifier)
        guard let data = try? JSONSerialization.data(withJSONObject: visibleItems, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return profileIdentifier + "\nblacklisted:\(blacklisted)\n" + json
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
        let automaticCPU = CustomButtonTouchBarItem(identifier: .init("test.studio.automaticCPU"), title: "CPU 100.0%")
        automaticCPU.image = NSImage(size: NSSize(width: 20, height: 20))
        let widthConfig: CanSetWidth = automaticCPU
        widthConfig.setWidth(value: 64)
        guard let automaticWidthConstraint = automaticCPU.view.constraints.first(where: { $0.firstAttribute == .width }) else {
            preconditionFailure("Automatic custom-button layout should retain its explicit width constraint")
        }
        automaticCPU.title = "CPU utilization 100.0%"
        precondition(automaticWidthConstraint.constant >= automaticCPU.studioNaturalContentWidth,
                     "Automatic layouts should grow their existing saved-width constraint when live button content grows")

        let date = CustomButtonTouchBarItem(identifier: .init("test.studio.date"), title: "")
        date.attributedTitle = "Wednesday, October 20, 2026".defaultTouchbarAttributedString
        date.setWidth(value: 64)

        let cpu = CustomButtonTouchBarItem(identifier: .init("test.studio.cpu"), title: "100.0%")
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
                     "Long Date and 100.0% CPU labels should override stale 64-point saved widths transiently")

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
        let slider = VolumeViewController(identifier:.init("test.volume"))
        precondition((0...100).contains(slider.sliderItem.doubleValue))
        print("PASS: clock, battery, CPU, focus timer and volume slider initialize with local data; malformed input returns an error without crashing.")
        print("NOT TESTED: physical taps, keyboard delivery, hardware changes, external services, Automation and private system toggles.")
    }
}
