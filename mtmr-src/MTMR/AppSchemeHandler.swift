//
//  AppSchemeHandler.swift
//  MTMR
//
//  Serves the bundled MTMR Designer web app and handles API calls natively
//  via a custom WKURLSchemeHandler, eliminating the need for an Express server.
//

import Cocoa
import WebKit

class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mtmr-app"

    private let webRoot: URL

    init(webRoot: URL) {
        self.webRoot = webRoot
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let path = url.path
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
        if path == "/api/studio" {
            do {
                if taskMethod(urlSchemeTask) == "POST" {
                    guard let data = urlSchemeTask.request.httpBody ?? readStreamBody(urlSchemeTask.request.httpBodyStream), let json = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw URLError(.badServerResponse) }
                    try StudioStore.shared.save(json)
                }
                respondJSON(urlSchemeTask,dict:["success":true,"workspace":StudioStore.shared.workspace,"activeProfile":StudioStore.shared.activeProfile,"enabled":AppSettings.touchBarEnabled])
            } catch { respondJSON(urlSchemeTask,dict:["success":false,"error":error.localizedDescription],statusCode:400) }
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
        if path == "/api/choose" { respondJSON(urlSchemeTask,dict:StudioStore.shared.choose(kind:value("kind"))); return }
        if path == "/api/pending-photos" {
            let selected = StudioStore.shared.pendingPhotoFiles
            StudioStore.shared.pendingPhotoFiles = []
            if selected.isEmpty { respondJSON(urlSchemeTask,dict:["success":true]); return }
            var isDirectory: ObjCBool = false
            if selected.count == 1, FileManager.default.fileExists(atPath:selected[0],isDirectory:&isDirectory),isDirectory.boolValue {
                var result = StudioStore.shared.photos(folder:selected[0]); result["folder"] = selected[0]; respondJSON(urlSchemeTask,dict:result)
            } else {
                var result = StudioStore.shared.photos(folder:"",selected:selected); result["folder"] = "Selected Finder photos"; respondJSON(urlSchemeTask,dict:result)
            }
            return
        }
        if path == "/api/photos" { respondJSON(urlSchemeTask,dict:StudioStore.shared.photos(folder:value("folder"))); return }
        if path == "/api/thumbnail" {
            if let data = StudioStore.shared.thumbnail(id:value("id")) { respond(urlSchemeTask,data:data,mimeType:"image/jpeg",statusCode:200) } else { respond(urlSchemeTask,data:Data(),mimeType:"text/plain",statusCode:404) }; return
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
        // No-op: requests complete synchronously or on the main queue
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
