import Cocoa
import ImageIO

final class StudioStore {
    static let shared = StudioStore()
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TouchBarStudio")
    var file: URL { directory.appendingPathComponent("workspace.json") }
    var workspace: [String: Any] = [:]
    var photoFiles: [String: URL] = [:]
    var pendingPhotoFiles: [String] = []
    var activeProfile = "default"
    var keepControlStrip: Bool { AppSettings.showControlStripState }
    var apiWorkspace: [String:Any] {
        var result = workspace
        var settings = result["settings"] as? [String:Any] ?? [:]
        settings["keepControlStrip"] = AppSettings.showControlStripState
        result["settings"] = settings
        return result
    }
    init() {
        if let data = try? Data(contentsOf: file), let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
            workspace = json
            if let keepControlStrip = (json["settings"] as? [String:Any])?["keepControlStrip"] as? Bool {
                AppSettings.showControlStripState = keepControlStrip
            }
        }
    }
    func save(_ data: [String:Any]) throws {
        guard data["version"] as? Int == 1, let profiles = data["profiles"] as? [String:[String:Any]], profiles["default"]?["items"] is [[String:Any]] else { throw NSError(domain:"Studio",code:1,userInfo:[NSLocalizedDescriptionKey:"A Default profile is required."]) }
        // Validate every layout before replacing the saved configuration.
        for (_, profile) in profiles {
            guard let items = profile["items"] as? [[String:Any]] else { throw NSError(domain:"Studio",code:2,userInfo:[NSLocalizedDescriptionKey:"Invalid profile items."]) }
            let encoded = try JSONSerialization.data(withJSONObject: safeItems(items))
            guard encoded.barItemDefinitions() != nil else { throw NSError(domain:"Studio",code:3,userInfo:[NSLocalizedDescriptionKey:"A profile contains an unsupported runtime control."]) }
        }
        var workspaceToSave = data
        var settings = data["settings"] as? [String:Any] ?? [:]
        // Older workspace files do not carry this preference. Keep the
        // current native setting and include its effective value next time
        // the workspace is saved.
        let keepControlStrip = settings["keepControlStrip"] as? Bool ?? AppSettings.showControlStripState
        settings["keepControlStrip"] = keepControlStrip
        workspaceToSave["settings"] = settings
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let encoded = try JSONSerialization.data(withJSONObject:workspaceToSave,options:[.prettyPrinted,.sortedKeys])
        if FileManager.default.fileExists(atPath:file.path) { try Data(contentsOf:file).write(to:directory.appendingPathComponent("workspace.previous.json"),options:.atomic) }
        try encoded.write(to:file,options:.atomic)
        workspace = workspaceToSave
        AppSettings.showControlStripState = keepControlStrip
        StudioLauncher.shared.configure()
        TouchBarController.shared.navigationStack = []
        TouchBarController.shared.reloadStandardConfig()
    }

    func setKeepControlStrip(_ enabled: Bool) throws {
        var updatedWorkspace = workspace
        var settings = updatedWorkspace["settings"] as? [String:Any] ?? [:]
        settings["keepControlStrip"] = enabled
        updatedWorkspace["settings"] = settings

        if FileManager.default.fileExists(atPath:file.path),
           let profiles = updatedWorkspace["profiles"] as? [String:[String:Any]],
           profiles["default"]?["items"] is [[String:Any]] {
            let encoded = try JSONSerialization.data(withJSONObject:updatedWorkspace,options:[.prettyPrinted,.sortedKeys])
            try encoded.write(to:file,options:.atomic)
        }

        workspace = updatedWorkspace
        AppSettings.showControlStripState = enabled
    }
    func safeItems(_ items: [[String:Any]]) -> [[String:Any]] {
        items.compactMap { original in
            var item = original
            let type = item["type"] as? String ?? ""
            if type.lowercased().contains("script") || type == "swipe" { return nil }
            for key in ["action", "longAction"] {
                if let value = item[key] as? String, !["hidKey","keyPress","openUrl","none"].contains(value) { item.removeValue(forKey:key) }
            }
            for key in ["actionAppleScript", "longActionAppleScript", "actionShellScript", "longActionShellScript"] { item.removeValue(forKey:key) }
            if let actions = item["actions"] as? [[String:Any]] { item["actions"] = actions.filter { ["hidKey","keyPress","openUrl"].contains($0["action"] as? String ?? "") } }
            if let children = item["items"] as? [[String:Any]] { item["items"] = safeItems(children) }
            return item
        }
    }
    func selectedItems(bundle: String?) -> [BarItemDefinition]? {
        guard let profiles = workspace["profiles"] as? [String:[String:Any]] else {
            let starter: [[String:Any]] = [["type":"escape"],["type":"timeButton","formatTemplate":"HH:mm"],["type":"group","title":"Audio","items":[["type":"volumeDown"],["type":"volumeUp"],["type":"mute"]]],["type":"volumeDown"],["type":"volumeUp"]]
            return (try? JSONSerialization.data(withJSONObject:starter))?.barItemDefinitions()
        }
        let matching = profiles.first { $0.key != "default" && $0.value["bundleId"] as? String == bundle && $0.value["enabled"] as? Bool != false }
        activeProfile = matching?.key ?? "default"
        guard let items = (matching?.value ?? profiles["default"])?["items"] as? [[String:Any]], let data = try? JSONSerialization.data(withJSONObject:safeItems(items)) else { return nil }
        return data.barItemDefinitions()
    }
    func choose(kind: String) -> [String:Any] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = kind == "folder"
        panel.canChooseFiles = kind != "folder"
        panel.allowsMultipleSelection = false
        if kind == "app" { panel.allowedFileTypes = ["app"]; panel.directoryURL = URL(fileURLWithPath:"/Applications") }
        guard panel.runModal() == .OK, let url = panel.url else { return ["success":true,"cancelled":true] }
        var result: [String:Any] = ["success":true,"path":url.path,"name":url.deletingPathExtension().lastPathComponent]
        if kind == "app" { result["bundleId"] = Bundle(url:url)?.bundleIdentifier }
        if kind == "image", let image = NSImage(contentsOf:url), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff), let png = rep.representation(using:.png,properties:[:]) { result["image"] = "data:image/png;base64," + png.base64EncodedString() }
        return result
    }
    func photos(folder: String, selected: [String]? = nil) -> [String:Any] {
        let url = URL(fileURLWithPath:folder)
        do {
            let files = try selected.map { $0.map { URL(fileURLWithPath:$0) } } ?? FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:[.contentModificationDateKey],options:.skipsHiddenFiles)
            photoFiles = [:]
            var output: [[String:Any]] = []
            for file in files where ["jpg","jpeg","png","heic","tif","tiff","webp","gif"].contains(file.pathExtension.lowercased()) {
                guard let source = CGImageSourceCreateWithURL(file as CFURL,nil), let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any] else { continue }
                let id = UUID().uuidString
                photoFiles[id] = file
                let date = (try? file.resourceValues(forKeys:[.contentModificationDateKey]))?.contentModificationDate
                output.append(["id":id,"name":file.lastPathComponent,"type":file.pathExtension.lowercased(),"width":props[kCGImagePropertyPixelWidth as String] ?? 0,"height":props[kCGImagePropertyPixelHeight as String] ?? 0,"date":date.map { ISO8601DateFormatter().string(from:$0) } ?? ""])
            }
            return ["success":true,"photos":output.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }]
        } catch { return ["success":false,"error":error.localizedDescription] }
    }
    func thumbnail(id: String) -> Data? {
        guard let url = photoFiles[id], let source = CGImageSourceCreateWithURL(url as CFURL,nil), let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:420,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage:cg).representation(using:.jpeg,properties:[.compressionFactor:0.8])
    }
}
