import Cocoa

/// Read-only runtime checks: decode defaults and render local status controls without sending actions.
enum StudioControlChecks {
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
