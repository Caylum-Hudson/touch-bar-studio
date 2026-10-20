import Cocoa
import Darwin

@main
enum StudioMain {
    static func main() {
        if CommandLine.arguments.contains("--native-slider-self-test") {
            StudioControlChecks.runNativeSliderChecks()
            return
        }
        if CommandLine.arguments.contains("--brightness-diagnostic") {
            runBrightnessDiagnostic(roundTrip: false)
            return
        }
        if CommandLine.arguments.contains("--brightness-round-trip") {
            runBrightnessDiagnostic(roundTrip: true)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of:"--control-self-test"), CommandLine.arguments.count > index+1 {
            do { try StudioControlChecks.run(path:CommandLine.arguments[index+1]) } catch { fatalError(error.localizedDescription) }
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            let store = StudioStore.shared
            store.workspace = ["version":1,"profiles":["default":["items":[["type":"staticButton","title":"Default"]]],"finder":["bundleId":"com.apple.finder","enabled":true,"items":[["type":"group","title":"Finder","items":[["type":"staticButton","title":"Nested"]]]]]]]
            let matched = store.selectedItems(bundle:"com.apple.finder")!
            precondition(store.activeProfile == "finder" && matched.count == 1)
            if case let .group(items:children) = matched[0].type { precondition(children.count == 1) } else { fatalError("Missing nested group") }
            precondition(store.selectedItems(bundle:"unmatched.app")!.count == 1 && store.activeProfile == "default")
            var profiles = store.workspace["profiles"] as! [String:[String:Any]]
            profiles["finder"]?["enabled"] = false
            store.workspace["profiles"] = profiles
            _ = store.selectedItems(bundle:"com.apple.finder")
            precondition(store.activeProfile == "default")
            let sanitized = store.safeItems([["type":"shellScriptTitledButton","source":["inline":"touch /tmp/never"]],["type":"staticButton","action":"shellScript","actions":[["action":"shellScript"],["action":"openUrl","url":"https://example.com"]]]])
            precondition(sanitized.count == 1 && sanitized[0]["action"] == nil && (sanitized[0]["actions"] as! [[String:Any]]).count == 1)
            let layoutData = "[{\"type\":\"staticButton\",\"title\":\"One\",\"width\":50,\"studioPosition\":120},{\"type\":\"staticButton\",\"title\":\"Two\",\"width\":100,\"studioPosition\":1080}]".data(using:.utf8)!
            let definitions = layoutData.barItemDefinitions()!
            precondition(StudioLayout.precise(definitions))
            let frames = StudioLayout.frames(definitions)
            precondition(frames[0].minX == 120 && frames[0].width == 50 && frames[1].minX == 985)
            print("PASS: native coordinate decode, width and right-edge clamping.")
            var sent = false
            precondition(!StudioPermissions.performKeyboardAction(isTrusted:{false}) { sent = true })
            precondition(!sent)
            precondition(StudioPermissions.performKeyboardAction(isTrusted:{true}) { sent = true })
            precondition(sent)
            print("PASS: missing permission blocks input; granted permission allows the action, without prompting.")
            print("PASS: native full profile replacement, unmatched and disabled fallback, recursive runtime decoding, script filtering.")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    private static func runBrightnessDiagnostic(roundTrip: Bool) {
        _ = NSApplication.shared
        let controller = BrightnessViewController(identifier: .init("diagnostic.brightness"), refreshInterval: 60)
        let diagnostic = controller.brightnessDiagnostic()
        guard let original = controller.currentBrightness else {
            print("FAIL: \(diagnostic)")
            exit(EXIT_FAILURE)
        }
        print("Brightness diagnostic: \(diagnostic)")
        print(String(format: "Current brightness: %.5f", original))
        guard roundTrip else { return }

        let target = original <= 0.97 ? original + 0.03 : original - 0.03
        var restoredValue: Float?
        var restorationStatus = "Restoration was not attempted"
        let targetMatched = withBrightnessRestoration(controller: controller, original: original, check: {
            let writeStatus = controller.setBrightnessForCheck(target)
            let (readback, attempts) = waitForBrightness(controller, target: target)
            print(String(format: "Round-trip target: %.5f; actual readback: %@ after %d read(s); status: %@",
                         target, readback.map { String(format: "%.5f", $0) } ?? "unavailable", attempts, writeStatus))
            return readback.map { abs($0 - target) <= 0.02 } ?? false
        }, restored: { value, status in
            restoredValue = value
            restorationStatus = status
        })
        print(String(format: "Restoration: original %.5f; actual readback %@; status: %@",
                     original, restoredValue.map { String(format: "%.5f", $0) } ?? "unavailable", restorationStatus))
        fflush(stdout)
        let restorationMatched = restoredValue.map { abs($0 - original) <= 0.02 } ?? false
        precondition(targetMatched, "Brightness round-trip target did not read back within tolerance")
        precondition(restorationMatched, "Brightness original value was not restored within tolerance")
        print("PASS: brightness write read back and original value was restored.")
    }

    private static func withBrightnessRestoration(
        controller: BrightnessViewController,
        original: Float,
        check: () -> Bool,
        restored: (Float?, String) -> Void
    ) -> Bool {
        let checkResult = check()
        let restorationStatus = controller.setBrightnessForCheck(original)
        let (restoredValue, attempts) = waitForBrightness(controller, target: original)
        restored(restoredValue, "\(restorationStatus); read back after \(attempts) read(s)")
        return checkResult
    }

    private static func waitForBrightness(_ controller: BrightnessViewController, target: Float) -> (Float?, Int) {
        var lastValue: Float?
        for attempt in 1...11 {
            lastValue = controller.currentBrightness
            if let value = lastValue, abs(value - target) <= 0.02 { return (value, attempt) }
            if attempt < 11 { Thread.sleep(forTimeInterval: 0.1) }
        }
        return (lastValue, 11)
    }
}
