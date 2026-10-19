import Cocoa

@main
enum StudioMain {
    static func main() {
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
            print("PASS: native full profile replacement, unmatched and disabled fallback, recursive runtime decoding, script filtering.")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
