import Cocoa
import Darwin

@main
enum StudioMain {
    static func main() {
        if CommandLine.arguments.contains("--metrics-diagnostic") {
            SystemMetrics.startMonitoring(.ram)
            SystemMetrics.startMonitoring(.gpu)
            SystemMetrics.startMonitoring(.cpuTemperature)
            RunLoop.current.run(until:Date().addingTimeInterval(2.2))
            let sample=SystemMetrics.snapshot()
            let ram=SystemMetrics.ramPercent(used:sample.ramUsedBytes,total:sample.ramTotalBytes).map { "RAM \($0)%" } ?? "RAM —"
            let gpu=SystemMetrics.gpuPercent(sample.gpuUtilization).map { "GPU \($0)%" } ?? "GPU —"
            let cpu=SystemMetrics.cpuTemperatureLabel(sample.cpuTemperatureCelsius)
            print("SYSTEM METRICS (local read-only sample): \(ram), \(gpu), \(cpu), \(SystemMetrics.unsupportedBoardLabel)")
            if let timing = SystemMetrics.cpuTemperatureReadTiming {
                print(String(format: "CPU SENSOR TIMING: one-time key inventory %.2f ms; cached-key sample %.2f ms", timing.inventoryMilliseconds, timing.sampleMilliseconds))
            }
            SystemMetrics.stopMonitoring(.ram)
            SystemMetrics.stopMonitoring(.gpu)
            SystemMetrics.stopMonitoring(.cpuTemperature)
            return
        }
        if CommandLine.arguments.contains("--native-slider-self-test") {
            StudioControlChecks.runNativeSliderChecks()
            return
        }
        if CommandLine.arguments.contains("--widget-lifecycle-self-test") {
            StudioControlChecks.runWidgetLifecycleChecks()
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
            if StudioCompactOverlaySelfTest() {
                print("PASS: Studio compact overlay suppresses its own close update; native AppKit overlay implementation is unchanged.")
            } else {
                print("UNAVAILABLE: scoped compact overlay; normal AppKit presenter remains the fallback.")
            }
            StudioControlChecks.runFocusRefreshPolicyChecks()
            StudioControlChecks.runWidgetLifecycleChecks()
            StudioControlChecks.runDockAutoResizeChecks()
            StudioControlChecks.runDockPreviewCacheChecks()
            StudioControlChecks.runStudioContentWidthChecks()
            precondition(AppSettings.shouldUseCompactControlStripPresentation(keepControlStrip: false, sliderExpanded: false) == false)
            precondition(AppSettings.shouldUseCompactControlStripPresentation(keepControlStrip: true, sliderExpanded: false) == true)
            precondition(AppSettings.shouldUseCompactControlStripPresentation(keepControlStrip: true, sliderExpanded: true) == false)
            print("PASS: Control Strip preference selects compact presentation, while an expanded slider temporarily uses the full bar.")
            let workspaceTestDirectory=FileManager.default.temporaryDirectory.appendingPathComponent("TouchBarStudio-workspace-selftest-\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at:workspaceTestDirectory,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:workspaceTestDirectory) }
            let workspaceTestFile=workspaceTestDirectory.appendingPathComponent("workspace.json")
            let previousBackup=workspaceTestDirectory.appendingPathComponent("workspace.previous.json")
            let corruptBytes=Data("{not valid workspace".utf8)
            let priorValidBytes=Data("previous valid backup".utf8)
            try! corruptBytes.write(to:workspaceTestFile)
            try! priorValidBytes.write(to:previousBackup)
            let invalidStore=StudioStore(directory:workspaceTestDirectory)
            precondition(invalidStore.workspaceLoadError != nil)
            let unconfirmedSave:[String:Any]=["version":1,"profiles":["default":["items":[]]]]
            do {
                try invalidStore.save(unconfirmedSave)
                fatalError("Unreadable workspace replacement should require explicit confirmation")
            } catch {
                precondition(error.localizedDescription.contains("could not be read"))
            }
            do {
                try StudioStore.validateUniqueProfileBundleIdentifiers([
                    "default":["items":[]],
                    "first":["bundleId":"com.example.duplicate","enabled":true,"items":[]],
                    "second":["bundleId":"com.example.duplicate","enabled":true,"items":[]]
                ])
                fatalError("Duplicate enabled app profiles should be rejected")
            } catch {
                precondition(error.localizedDescription.contains("unique bundle identifiers"))
            }
            let unreadableBackup=try! StudioStore.preserveWorkspaceBeforeReplacement(file:workspaceTestFile,directory:workspaceTestDirectory)
            precondition(unreadableBackup?.lastPathComponent.hasPrefix("workspace.unreadable-") == true)
            precondition((try! Data(contentsOf:unreadableBackup!)) == corruptBytes)
            precondition((try! Data(contentsOf:previousBackup)) == priorValidBytes)
            let validWorkspace:[String:Any]=["version":1,"profiles":["default":["items":[]]]]
            try! JSONSerialization.data(withJSONObject:validWorkspace).write(to:workspaceTestFile)
            let validBackup=try! StudioStore.preserveWorkspaceBeforeReplacement(file:workspaceTestFile,directory:workspaceTestDirectory)
            precondition(validBackup == previousBackup)
            precondition(try! JSONSerialization.jsonObject(with:Data(contentsOf:previousBackup)) is [String:Any])
            print("PASS: unreadable workspace bytes and the prior valid backup are preserved separately before replacement.")
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
            store.workspace = ["profiles":[
                "default":["items":[["type":"staticButton","title":"Default fallback"]]],
                "resolve":["bundleId":"com.blackmagic-design.DaVinciResolve","enabled":true,
                            "items":[["type":"staticButton","title":"Resolve fallback"]],
                            "resolvePageLayouts":[
                                "edit":[["type":"staticButton","title":"Edit layout"]],
                                "color":[["type":"staticButton","title":"Color layout"],["type":"shellScriptTitledButton","source":["inline":"touch /tmp/never"]]]
                            ]]
            ]]
            let editPage=store.selectedItems(bundle:"com.blackmagic-design.DaVinciResolve",resolvePage:"edit")!
            precondition(store.activeProfile=="resolve" && store.activeResolvePage=="edit" && editPage.count==1)
            if case let .staticButton(title) = editPage[0].type { precondition(title=="Edit layout") } else { fatalError("Edit page layout was not selected") }
            let colorPage=store.selectedItems(bundle:"com.blackmagic-design.DaVinciResolve",resolvePage:"color")!
            precondition(store.activeResolvePage=="color" && colorPage.count==1)
            if case let .staticButton(title) = colorPage[0].type { precondition(title=="Color layout") } else { fatalError("Color page layout was not selected") }
            let missingPage=store.selectedItems(bundle:"com.blackmagic-design.DaVinciResolve",resolvePage:"fusion")!
            precondition(store.activeResolvePage=="fusion" && missingPage.count==1)
            if case let .staticButton(title) = missingPage[0].type { precondition(title=="Resolve fallback") } else { fatalError("Missing page did not use profile fallback") }
            let unknownPage=store.selectedItems(bundle:"com.blackmagic-design.DaVinciResolve",resolvePage:"not-a-page")!
            precondition(store.activeResolvePage==nil && unknownPage.count==1)
            let otherApp=store.selectedItems(bundle:"com.example.editor")!
            precondition(store.activeProfile=="default" && store.activeResolvePage==nil && otherApp.count==1)
            if case let .staticButton(title) = otherApp[0].type { precondition(title=="Default fallback") } else { fatalError("Non-Resolve app did not use Default") }
            let sanitized = store.safeItems([["type":"shellScriptTitledButton","source":["inline":"touch /tmp/never"]],["type":"staticButton","action":"shellScript","actions":[["action":"shellScript"],["action":"openUrl","url":"https://example.com"]]]])
            precondition(sanitized.count == 1 && sanitized[0]["action"] == nil && (sanitized[0]["actions"] as! [[String:Any]]).count == 1)
            let layoutData = "[{\"type\":\"staticButton\",\"title\":\"One\",\"width\":50,\"studioPosition\":120},{\"type\":\"staticButton\",\"title\":\"Two\",\"width\":100,\"studioPosition\":1080}]".data(using:.utf8)!
            let definitions = layoutData.barItemDefinitions()!
            precondition(StudioLayout.precise(definitions))
            let frames = StudioLayout.frames(definitions)
            precondition(frames[0].minX == 120 && frames[0].width == 50 && frames[1].minX == 1080)
            print("PASS: native coordinate decode, width and explicit-position preservation at the bar edge.")
            var sent = false
            precondition(!StudioPermissions.performKeyboardAction(isTrusted:{false}) { sent = true })
            precondition(!sent)
            precondition(StudioPermissions.performKeyboardAction(isTrusted:{true}) { sent = true })
            precondition(sent)
            print("PASS: missing permission blocks input; granted permission allows the action, without prompting.")
            print("PASS: native profile replacement, app and page selection, missing/unknown page fallback, recursive decoding, script filtering.")
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
