//
//  AppSchemeHandler.swift
//  MTMR
//
//  Serves the bundled MTMR Designer web app and handles API calls natively
//  via a custom WKURLSchemeHandler, eliminating the need for an Express server.
//

import Cocoa
import WebKit

enum StudioWorkspaceResponsePolicy {
    static func includesWorkspace(method: String, statusOnly: Bool) -> Bool {
        method != "GET" || !statusOnly
    }
}

private final class PhotoRequestCancellation {
    private let lock=NSLock()
    private var workCancelled=false
    private var stopped=false
    let isScan: Bool
    init(isScan: Bool = false) { self.isScan=isScan }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return workCancelled || stopped }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancelWork() { lock.lock(); workCancelled=true; lock.unlock() }
    func cancel() { lock.lock(); workCancelled=true; stopped=true; lock.unlock() }
}

class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mtmr-app"

    private let webRoot: URL
    private let photoQueue: OperationQueue = {
        let queue=OperationQueue()
        queue.name="TouchBarStudio.PhotoIO"
        queue.maxConcurrentOperationCount=2
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var photoRequests: [ObjectIdentifier:PhotoRequestCancellation] = [:]
    private var latestPhotoScan: UInt64 = 0

    init(webRoot: URL) {
        self.webRoot = webRoot
        super.init()
    }

    deinit {
        photoRequests.values.forEach { $0.cancel() }
        photoQueue.cancelAllOperations()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let path = url.path
        if path == "/api/keyboard-permission" {
            let opened = taskMethod(urlSchemeTask) != "POST" || StudioPermissions.openSettings()
            var response: [String: Any] = ["success": opened]
            StudioPermissions.statusFields.forEach { response[$0.key] = $0.value }
            respondJSON(urlSchemeTask,dict:response)
            return
        }
        if path == "/api/touchbar" {
            if taskMethod(urlSchemeTask) == "POST" {
                guard let data = urlSchemeTask.request.httpBody ?? readStreamBody(urlSchemeTask.request.httpBodyStream),
                      let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                      let enabled = json["enabled"] as? Bool else {
                    respondJSON(urlSchemeTask,dict:["success":false,"error":"Expected an enabled boolean."],statusCode:400)
                    return
                }
                TouchBarController.shared.setEnabled(enabled)
            }
            respondJSON(urlSchemeTask,dict:["success":true,"enabled":AppSettings.touchBarEnabled])
            return
        }
        if path == "/api/control-strip" {
            if taskMethod(urlSchemeTask) == "POST" {
                guard let data = urlSchemeTask.request.httpBody ?? readStreamBody(urlSchemeTask.request.httpBodyStream),
                      let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                      let enabled = json["enabled"] as? Bool else {
                    respondJSON(urlSchemeTask,dict:["success":false,"error":"Expected an enabled boolean."],statusCode:400)
                    return
                }
                do {
                    try StudioStore.shared.setKeepControlStrip(enabled)
                    TouchBarController.shared.resetControlStrip()
                    (NSApp.delegate as? AppDelegate)?.createMenu()
                } catch {
                    respondJSON(urlSchemeTask,dict:["success":false,"error":error.localizedDescription],statusCode:400)
                    return
                }
            }
            respondJSON(urlSchemeTask,dict:["success":true,"keepControlStrip":AppSettings.showControlStripState])
            return
        }
        if path == "/api/studio" {
            do {
                if taskMethod(urlSchemeTask) == "POST" {
                    guard let data = urlSchemeTask.request.httpBody ?? readStreamBody(urlSchemeTask.request.httpBodyStream), let request = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw URLError(.badServerResponse) }
                    let workspace = request["workspace"] as? [String:Any] ?? request
                    try StudioStore.shared.save(workspace,allowReplacingUnreadable:request["replaceUnreadable"] as? Bool == true)
                }
                let store=StudioStore.shared
                let controller=TouchBarController.shared
                let runtimeProfile=(store.workspace["profiles"] as? [String:[String:Any]])?[store.activeProfile]
                let runtimeLayouts=runtimeProfile?["resolvePageLayouts"] as? [String:[[String:Any]]]
                let query=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
                let statusOnly=query.contains { $0.name == "statusOnly" && $0.value == "1" }
                var response: [String: Any] = ["success": true,"workspaceLoadError":store.workspaceLoadError.map { $0 as Any } ?? NSNull(),"activeProfile":store.activeProfile,"enabled":AppSettings.touchBarEnabled,"keepControlStrip":AppSettings.showControlStripState,"frontmostBundleId":controller.frontmostApplicationIdentifier.map { $0 as Any } ?? NSNull(),"activeResolvePage":store.activeResolvePage.map { $0 as Any } ?? NSNull(),"resolvePageOverride":controller.resolvePageOverride.map { $0 as Any } ?? NSNull(),"resolvePageMode":controller.resolvePageOverride == nil ? "automatic" : "manual","resolvePageDetection":store.resolvePageDetectionStatus,"activeResolvePageFallback":store.activeResolvePage.map { runtimeLayouts?[$0] == nil } ?? false]
                if StudioWorkspaceResponsePolicy.includesWorkspace(method:taskMethod(urlSchemeTask),statusOnly:statusOnly) {
                    response["workspace"] = store.apiWorkspace
                }
                response["layoutCapacity"] = controller.studioLayoutCapacity.map { $0 as Any } ?? NSNull()
                StudioPermissions.statusFields.forEach { response[$0.key] = $0.value }
                respondJSON(urlSchemeTask,dict:response)
            } catch { respondJSON(urlSchemeTask,dict:["success":false,"error":error.localizedDescription],statusCode:400) }
            return
        }
        if path == "/api/resolve-page" {
            guard taskMethod(urlSchemeTask)=="POST",
                  let data=urlSchemeTask.request.httpBody ?? readStreamBody(urlSchemeTask.request.httpBodyStream),
                  let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {
                respondJSON(urlSchemeTask,dict:["success":false,"error":"A Resolve page selection is required."],statusCode:400); return
            }
            let selected=json["page"] as? String ?? "auto"
            let page=selected=="auto" ? nil : selected
            if let page,ResolvePageDetection.labels[page]==nil {
                respondJSON(urlSchemeTask,dict:["success":false,"error":"Unknown Resolve page."],statusCode:400); return
            }
            TouchBarController.shared.setResolvePageOverride(page)
            respondJSON(urlSchemeTask,dict:["success":true,"resolvePageOverride":page.map { $0 as Any } ?? NSNull(),"resolvePageMode":page == nil ? "automatic" : "manual"])
            return
        }
        let query = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
        func value(_ name: String) -> String { query.first { $0.name == name }?.value ?? "" }
        if path == "/api/apps" {
            var apps: [[String:Any]] = []
            for root in ["/Applications", "/System/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path] {
                for url in (try? FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:root),includingPropertiesForKeys:nil)) ?? [] where url.pathExtension == "app" {
                    if let id = Bundle(url:url)?.bundleIdentifier { apps.append(["name":url.deletingPathExtension().lastPathComponent,"bundleId":id]) }
                }
            }
            respondJSON(urlSchemeTask,dict:["success":true,"apps":apps.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }]); return
        }
        if path == "/api/dock-preview" {
            let bundle=NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let definitions = StudioStore.shared.selectedItems(bundle:bundle,resolvePage:bundle=="com.blackmagic-design.DaVinciResolve" ? TouchBarController.shared.effectiveResolvePage : nil) ?? []
            let dockDefinition = definitions.first { if case .dock = $0.type { return true }; return false }
            var filterPattern: String?
            if let dockDefinition, case let .dock(autoResize: _, filter: filter) = dockDefinition.type { filterPattern = filter }
            if let requestedFilter = query.first(where: { $0.name == "filter" }) {
                let value = requestedFilter.value ?? ""
                filterPattern = value.isEmpty ? nil : value
            }
            respondJSON(urlSchemeTask, dict: DockPreviewSnapshotCache.shared.response(filterPattern: filterPattern, sinceRevision: value("sinceRevision")))
            return
        }
        if path == "/api/choose" { respondJSON(urlSchemeTask,dict:StudioStore.shared.choose(kind:value("kind"))); return }
        if path == "/api/pending-photos" {
            let selected = StudioStore.shared.pendingPhotoFiles
            StudioStore.shared.pendingPhotoFiles = []
            if selected.isEmpty { respondJSON(urlSchemeTask,dict:["success":true]); return }
            var isDirectory: ObjCBool = false
            if selected.count == 1, FileManager.default.fileExists(atPath:selected[0],isDirectory:&isDirectory),isDirectory.boolValue {
                startPhotoScan(urlSchemeTask,folder:selected[0],selected:nil,folderLabel:selected[0])
            } else {
                startPhotoScan(urlSchemeTask,folder:"",selected:selected,folderLabel:"Selected Finder photos")
            }
            return
        }
        if path == "/api/photos" { startPhotoScan(urlSchemeTask,folder:value("folder"),selected:nil,folderLabel:value("folder")); return }
        if path == "/api/thumbnail" {
            guard let photoURL=StudioStore.shared.photoFiles[value("id")] else { respond(urlSchemeTask,data:Data(),mimeType:"text/plain",statusCode:404); return }
            startThumbnail(urlSchemeTask,url:photoURL); return
        }
        if path == "/api/open" {
            let path = value("path")
            let ok = path.hasPrefix("/") && NSWorkspace.shared.open(URL(fileURLWithPath:path))
            respondJSON(urlSchemeTask,dict:["success":ok]); return
        }

        if path.hasPrefix("/api/") {
            handleAPIRequest(urlSchemeTask, path: path)
        } else {
            serveStaticFile(urlSchemeTask, path: path)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        photoRequests.removeValue(forKey:ObjectIdentifier(urlSchemeTask))?.cancel()
    }

    func startPhotoScan(_ task: WKURLSchemeTask, folder: String, selected: [String]?, folderLabel: String) {
        let taskID=ObjectIdentifier(task)
        photoRequests.values.filter(\.isScan).forEach { $0.cancelWork() }
        let cancellation=PhotoRequestCancellation(isScan:true)
        photoRequests[taskID]=cancellation
        latestPhotoScan &+= 1
        let generation=latestPhotoScan
        photoQueue.addOperation { [weak self, weak task] in
            let result=StudioStore.scanPhotos(folder:folder,selected:selected,shouldCancel:{ cancellation.isCancelled })
            DispatchQueue.main.async {
                guard let self, self.photoRequests[taskID] === cancellation else { return }
                self.photoRequests.removeValue(forKey:taskID)
                guard !cancellation.isStopped, let task else { return }
                guard generation == self.latestPhotoScan else {
                    self.respondJSON(task,dict:["success":false,"error":"A newer photo scan replaced this request."],statusCode:409)
                    return
                }
                guard result.response["success"] as? Bool == true else {
                    self.respondJSON(task,dict:result.response,statusCode:400)
                    return
                }
                StudioStore.shared.photoFiles=result.files
                var response=result.response
                response["folder"]=folderLabel
                self.respondJSON(task,dict:response)
            }
        }
    }

    private func startThumbnail(_ task: WKURLSchemeTask, url: URL) {
        let taskID=ObjectIdentifier(task)
        let cancellation=PhotoRequestCancellation()
        photoRequests[taskID]=cancellation
        photoQueue.addOperation { [weak self, weak task] in
            let data=cancellation.isCancelled ? nil : StudioStore.thumbnail(at:url)
            DispatchQueue.main.async {
                guard let self, self.photoRequests[taskID] === cancellation else { return }
                self.photoRequests.removeValue(forKey:taskID)
                guard !cancellation.isStopped, let task else { return }
                if let data { self.respond(task,data:data,mimeType:"image/jpeg",statusCode:200) }
                else { self.respond(task,data:Data(),mimeType:"text/plain",statusCode:404) }
            }
        }
    }

    private func taskMethod(_ task: WKURLSchemeTask) -> String { task.request.httpMethod ?? "GET" }

    // MARK: - Static File Serving

    private func serveStaticFile(_ task: WKURLSchemeTask, path: String) {
        var filePath = path
        if filePath == "/" || filePath.isEmpty { filePath = "/index.html" }

        // Remove leading slash for path construction
        let relativePath = String(filePath.dropFirst())
        let fileURL = webRoot.appendingPathComponent(relativePath).standardizedFileURL
        guard fileURL.path.hasPrefix(webRoot.standardizedFileURL.path + "/") else { respond(task,data:Data(),mimeType:"text/plain",statusCode:403); return }

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            // For SPA routing, serve index.html for non-file paths
            if !relativePath.contains(".") {
                let indexURL = webRoot.appendingPathComponent("index.html")
                if let indexData = try? Data(contentsOf: indexURL) {
                    respond(task, data: indexData, mimeType: "text/html", statusCode: 200)
                    return
                }
            }
            respond(task, data: "Not Found".data(using: .utf8)!, mimeType: "text/plain", statusCode: 404)
            return
        }

        let mimeType = mimeTypeForExtension(fileURL.pathExtension)
        respond(task, data: data, mimeType: mimeType, statusCode: 200)
    }

    // MARK: - API Handlers

    private func handleAPIRequest(_ task: WKURLSchemeTask, path: String) {
        switch path {
        case "/api/load-mtmr":
            handleLoadMTMR(task)
        case "/api/save-mtmr":
            handleSaveMTMR(task)
        case "/api/config-path":
            handleConfigPath(task)
        case "/api/health":
            respondJSON(task, dict: [
                "success": true,
                "message": "MTMR Designer (bundled) is running",
                "timestamp": ISO8601DateFormatter().string(from: Date()),
            ])
        case "/api/check-mtmr-running":
            respondJSON(task, dict: ["success": true, "isRunning": true])
        case "/api/launch-mtmr":
            respondJSON(task, dict: ["success": true, "message": "MTMR is already running"])
        default:
            respond(task, data: "Not Found".data(using: .utf8)!, mimeType: "text/plain", statusCode: 404)
        }
    }

    private func handleLoadMTMR(_ task: WKURLSchemeTask) {
        let configPath = standardConfigPath

        guard FileManager.default.fileExists(atPath: configPath) else {
            respondJSON(task, dict: ["success": true, "data": [], "message": "No config file found, returning empty array"] as [String: Any])
            return
        }

        do {
            let content = try String(contentsOfFile: configPath, encoding: .utf8)
            // Parse JSON (strip comments by using a simple approach)
            if let data = content.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                respondJSON(task, dict: ["success": true, "data": json, "message": "Successfully loaded MTMR configuration"] as [String: Any])
            } else {
                respondJSON(task, dict: ["success": true, "data": [], "message": "Loaded empty configuration"] as [String: Any])
            }
        } catch {
            respondJSON(task, dict: ["success": false, "error": "Failed to read MTMR config: \(error.localizedDescription)"], statusCode: 500)
        }
    }

    private func handleSaveMTMR(_ task: WKURLSchemeTask) {
        guard let body = task.request.httpBody ?? readStreamBody(task.request.httpBodyStream),
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            respondJSON(task, dict: ["success": false, "error": "Invalid data format: expected { data: [...] }"], statusCode: 400)
            return
        }

        let configPath = standardConfigPath
        let dir = (configPath as NSString).deletingLastPathComponent

        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])
            try data.write(to: URL(fileURLWithPath: configPath))
            respondJSON(task, dict: ["success": true, "message": "Successfully updated MTMR configuration"])
        } catch {
            respondJSON(task, dict: ["success": false, "error": "Failed to write config: \(error.localizedDescription)"], statusCode: 500)
        }
    }

    private func handleConfigPath(_ task: WKURLSchemeTask) {
        respondJSON(task, dict: ["success": true, "path": standardConfigPath, "message": "MTMR configuration file path"])
    }

    // MARK: - Response Helpers

    private func respond(_ task: WKURLSchemeTask, data: Data, mimeType: String, statusCode: Int) {
        let url = task.request.url ?? URL(string: "\(AppSchemeHandler.scheme)://app/")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func respondJSON(_ task: WKURLSchemeTask, dict: [String: Any], statusCode: Int = 200) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            let fallback = "{\"success\":false,\"error\":\"JSON serialization failed\"}".data(using: .utf8)!
            respond(task, data: fallback, mimeType: "application/json", statusCode: 500)
            return
        }
        respond(task, data: data, mimeType: "application/json", statusCode: statusCode)
    }

    private func readStreamBody(_ stream: InputStream?) -> Data? {
        guard let stream = stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) }
            else { break }
        }
        return data
    }

    // MARK: - MIME Types

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html":  return "text/html"
        case "css":   return "text/css"
        case "js":    return "application/javascript"
        case "json":  return "application/json"
        case "png":   return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":   return "image/gif"
        case "svg":   return "image/svg+xml"
        case "ico":   return "image/x-icon"
        case "woff":  return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf":   return "font/ttf"
        case "map":   return "application/json"
        default:      return "application/octet-stream"
        }
    }
}
