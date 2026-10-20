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
            if let pattern = source["matchAppId"] as? String, let bundleIdentifier {
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
        precondition(StudioFocusRefreshPolicy.shouldRefresh(previous: mail, next: editor),
                     "A matchAppId visibility change should refresh the bar")
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
