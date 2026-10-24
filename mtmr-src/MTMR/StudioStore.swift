import Cocoa
import ImageIO

final class StudioStore {
    static let shared = StudioStore()
    let directory: URL
    var file: URL { directory.appendingPathComponent("workspace.json") }
    var workspace: [String: Any] = [:]
    private(set) var workspaceLoadError: String?
    var photoFiles: [String: URL] = [:]
    var pendingPhotoFiles: [String] = []
    var activeProfile = "default"
    var activeResolvePage: String?
    var resolvePageDetectionStatus = "inactive"
    var keepControlStrip: Bool { AppSettings.showControlStripState }
    var apiWorkspace: [String:Any] {
        var result = workspace
        var settings = result["settings"] as? [String:Any] ?? [:]
        settings["keepControlStrip"] = AppSettings.showControlStripState
        result["settings"] = settings
        return result
    }
    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TouchBarStudio")) {
        self.directory = directory
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let data = try Data(contentsOf: file)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String:Any], Self.isWorkspace(json) else {
                workspaceLoadError = "The saved workspace is not a valid version 1 workspace."
                return
            }
            workspace = json
            if let keepControlStrip = (json["settings"] as? [String:Any])?["keepControlStrip"] as? Bool {
                AppSettings.showControlStripState = keepControlStrip
            }
        } catch {
            workspaceLoadError = "The saved workspace could not be read: \(error.localizedDescription)"
        }
    }

    private static func isWorkspace(_ json: [String:Any]) -> Bool {
        json["version"] as? Int == 1 &&
        (json["profiles"] as? [String:[String:Any]])?["default"]?["items"] is [[String:Any]]
    }

    static func validateUniqueProfileBundleIdentifiers(_ profiles: [String:[String:Any]]) throws {
        var bundleIdentifiers: [String] = []
        for (key, profile) in profiles where key != "default" && profile["enabled"] as? Bool != false {
            guard let bundleIdentifier = profile["bundleId"] as? String,
                  !bundleIdentifier.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
                throw NSError(domain:"Studio",code:8,userInfo:[NSLocalizedDescriptionKey:"Enabled app profiles need a bundle identifier."])
            }
            bundleIdentifiers.append(bundleIdentifier)
        }
        guard Set(bundleIdentifiers).count == bundleIdentifiers.count else {
            throw NSError(domain:"Studio",code:7,userInfo:[NSLocalizedDescriptionKey:"Enabled app profiles must use unique bundle identifiers."])
        }
    }

    @discardableResult
    static func preserveWorkspaceBeforeReplacement(file: URL, directory: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        let isValid = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any]
        let backup: URL
        if let isValid, Self.isWorkspace(isValid) {
            backup = directory.appendingPathComponent("workspace.previous.json")
        } else {
            backup = directory.appendingPathComponent("workspace.unreadable-\(UUID().uuidString).json")
        }
        try data.write(to: backup, options: .atomic)
        return backup
    }
    func save(_ data: [String:Any], allowReplacingUnreadable: Bool = false) throws {
        guard data["version"] as? Int == 1, let profiles = data["profiles"] as? [String:[String:Any]], profiles["default"]?["items"] is [[String:Any]] else { throw NSError(domain:"Studio",code:1,userInfo:[NSLocalizedDescriptionKey:"A Default profile is required."]) }
        if workspaceLoadError != nil && !allowReplacingUnreadable {
            throw NSError(domain:"Studio",code:6,userInfo:[NSLocalizedDescriptionKey:"The saved workspace could not be read. Import a workspace or explicitly confirm replacement before saving."])
        }
        try Self.validateUniqueProfileBundleIdentifiers(profiles)
        // Validate every layout before replacing the saved configuration.
        for (_, profile) in profiles {
            guard let items = profile["items"] as? [[String:Any]] else { throw NSError(domain:"Studio",code:2,userInfo:[NSLocalizedDescriptionKey:"Invalid profile items."]) }
            let encoded = try JSONSerialization.data(withJSONObject: safeItems(items))
            guard encoded.barItemDefinitions() != nil else { throw NSError(domain:"Studio",code:3,userInfo:[NSLocalizedDescriptionKey:"A profile contains an unsupported runtime control."]) }
            if let pageLayouts = profile["resolvePageLayouts"] {
                guard let layouts = pageLayouts as? [String:[[String:Any]]] else { throw NSError(domain:"Studio",code:4,userInfo:[NSLocalizedDescriptionKey:"Invalid Resolve page layouts."]) }
                for (page, pageItems) in layouts {
                    guard ResolvePageDetection.labels[page] != nil,
                          let pageData = try? JSONSerialization.data(withJSONObject:safeItems(pageItems)),
                          pageData.barItemDefinitions() != nil else {
                        throw NSError(domain:"Studio",code:5,userInfo:[NSLocalizedDescriptionKey:"A Resolve page layout contains an unsupported control."])
                    }
                }
            }
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
        try Self.preserveWorkspaceBeforeReplacement(file:file,directory:directory)
        try encoded.write(to:file,options:.atomic)
        workspace = workspaceToSave
        workspaceLoadError = nil
        AppSettings.showControlStripState = keepControlStrip
        StudioLauncher.shared.configure()
        TouchBarController.shared.resetStudioNavigation()
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
    func selectedItems(bundle: String?, resolvePage: String? = nil) -> [BarItemDefinition]? {
        activeResolvePage = nil
        guard let profiles = workspace["profiles"] as? [String:[String:Any]] else {
            let starter: [[String:Any]] = [["type":"escape"],["type":"timeButton","formatTemplate":"HH:mm"],["type":"group","title":"Audio","items":[["type":"volumeDown"],["type":"volumeUp"],["type":"mute"]]],["type":"volumeDown"],["type":"volumeUp"]]
            return (try? JSONSerialization.data(withJSONObject:starter))?.barItemDefinitions()
        }
        let matching = bundle.flatMap { bundleIdentifier in
            profiles.first { $0.key != "default" && $0.value["bundleId"] as? String == bundleIdentifier && $0.value["enabled"] as? Bool != false }
        }
        activeProfile = matching?.key ?? "default"
        let matchingProfile = matching?.value
        let selectedProfile = matchingProfile ?? profiles["default"]
        var sourceItems = selectedProfile?["items"] as? [[String:Any]]
        if bundle == "com.blackmagic-design.DaVinciResolve", matchingProfile?["bundleId"] as? String == "com.blackmagic-design.DaVinciResolve" {
            if let resolvePage, ResolvePageDetection.labels[resolvePage] != nil {
                activeResolvePage = resolvePage
                let pageLayouts = matchingProfile?["resolvePageLayouts"] as? [String:[[String:Any]]]
                sourceItems = pageLayouts?[resolvePage] ?? sourceItems
            }
        }
        guard let items = sourceItems, let data = try? JSONSerialization.data(withJSONObject:safeItems(items)) else { return nil }
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
        if kind == "image", let png = Self.thumbnailPNG(at:url) { result["image"] = "data:image/png;base64," + png.base64EncodedString() }
        return result
    }

    static func thumbnailPNG(at url: URL, maxPixelSize: Int = 512) -> Data? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL,nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceThumbnailMaxPixelSize:maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform:true
              ] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])
    }
    func photos(folder: String, selected: [String]? = nil) -> [String:Any] {
        let result = Self.scanPhotos(folder:folder,selected:selected)
        if result.response["success"] as? Bool == true { photoFiles = result.files }
        return result.response
    }

    static func scanPhotos(folder: String, selected: [String]? = nil, shouldCancel: () -> Bool = { false }) -> (response: [String:Any], files: [String:URL]) {
        let url = URL(fileURLWithPath:folder)
        do {
            let files = try selected.map { $0.map { URL(fileURLWithPath:$0) } } ?? FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:[.contentModificationDateKey],options:.skipsHiddenFiles)
            var photoFiles: [String:URL] = [:]
            var output: [[String:Any]] = []
            for file in files where ["jpg","jpeg","png","heic","tif","tiff","webp","gif"].contains(file.pathExtension.lowercased()) {
                if shouldCancel() { return (["success":false,"error":"Photo scan cancelled."],[:]) }
                let dimensions: (Any,Any)? = autoreleasepool {
                    guard let source=CGImageSourceCreateWithURL(file as CFURL,nil),
                          let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],
                          let width=properties[kCGImagePropertyPixelWidth as String],
                          let height=properties[kCGImagePropertyPixelHeight as String] else { return nil }
                    return (width,height)
                }
                guard let dimensions else { continue }
                let id = UUID().uuidString
                photoFiles[id] = file
                let date = (try? file.resourceValues(forKeys:[.contentModificationDateKey]))?.contentModificationDate
                output.append(["id":id,"name":file.lastPathComponent,"type":file.pathExtension.lowercased(),"width":dimensions.0,"height":dimensions.1,"date":date.map { ISO8601DateFormatter().string(from:$0) } ?? ""])
            }
            return (["success":true,"photos":output.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }],photoFiles)
        } catch { return (["success":false,"error":error.localizedDescription],[:]) }
    }
    func thumbnail(id: String) -> Data? {
        guard let url = photoFiles[id] else { return nil }
        return Self.thumbnail(at:url)
    }
    static func thumbnail(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil), let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:420,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage:cg).representation(using:.jpeg,properties:[.compressionFactor:0.8])
    }
}
