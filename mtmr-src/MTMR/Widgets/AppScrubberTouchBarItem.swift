//
//  AppScrubberTouchBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 18.04.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.

import Cocoa

private let iconWidth: CGFloat = 32

private final class DockScrollView: NSScrollView {
    var didLayout: ((CGFloat) -> Void)?

    override func layout() {
        super.layout()
        didLayout?(bounds.width)
    }
}

class AppScrubberTouchBarItem: NSCustomTouchBarItem {
    private var scrollView = DockScrollView()
    private var autoResize: Bool = false
    private var widthConstraint: NSLayoutConstraint?
    private let filter: NSRegularExpression?
    private var stackView: NSStackView?
    private var usesPositionedWidth = false
    private var preferredContentWidth: CGFloat = 0
    private var preferredWidthDidChange: (() -> Void)?
    private var lastFitWidth: CGFloat?
    private var lastFitNaturalWidth: CGFloat?

    var supportsAutoResize: Bool { autoResize }
    var naturalContentWidth: CGFloat { preferredContentWidth }

    private var persistentAppIdentifiers: [String] = []

    private var frontmostApplicationIdentifier: String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private var applications: [DockItem] = []
    private var items: [DockBarItem] = []

    init(identifier: NSTouchBarItem.Identifier, autoResize: Bool = false, filter: NSRegularExpression? = nil) {
        self.filter = filter
        super.init(identifier: identifier)
        self.autoResize = autoResize
        view = scrollView
        if autoResize {
            scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            scrollView.didLayout = { [weak self] width in self?.fitContent(to: width) }
        }

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(hardReloadItems), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(hardReloadItems), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(softReloadItems), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        persistentAppIdentifiers = AppSettings.dockPersistentAppIds
        hardReloadItems()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func hardReloadItems() {
        let snapshot = DockAppSnapshotSource.load(filter: filter, persistentIdentifiers: persistentAppIdentifiers)
        applications = snapshot.applications
        reloadData()
        softReloadItems()
        updateSize()
    }
    
    @objc func softReloadItems() {
        let frontMostAppId = self.frontmostApplicationIdentifier
        let runningAppsIds = NSWorkspace.shared.runningApplications.map { $0.bundleIdentifier }
        for barItem in items {
            let bundleId = barItem.dockItem.bundleIdentifier
            barItem.isRunning = runningAppsIds.contains(bundleId)
            barItem.isFrontmost = frontMostAppId == bundleId
        }
    }
    
    func updateSize() {
        if self.autoResize {
            preferredContentWidth = DockAppSnapshotSource.preferredWidth(appCount: items.count)
            if !usesPositionedWidth {
                if let widthConstraint {
                    widthConstraint.constant = preferredContentWidth
                } else {
                    let constraint = scrollView.widthAnchor.constraint(equalToConstant: preferredContentWidth)
                    constraint.priority = .defaultHigh
                    constraint.isActive = true
                    widthConstraint = constraint
                }
            }
            preferredWidthDidChange?()
        }
    }

    func usePositionedWidth(onChange: @escaping () -> Void) {
        usesPositionedWidth = true
        widthConstraint?.isActive = false
        preferredWidthDidChange = onChange
    }

    func fitContent(to width: CGFloat) {
        guard autoResize, let stackView else { return }
        let widthChanged = lastFitWidth.map { abs($0 - width) > 0.01 } ?? true
        let contentChanged = lastFitNaturalWidth.map { abs($0 - preferredContentWidth) > 0.01 } ?? true
        guard widthChanged || contentChanged else { return }
        lastFitWidth = width
        lastFitNaturalWidth = preferredContentWidth
        let naturalWidth = max(1, preferredContentWidth)
        let scale = min(1, max(0, width) / naturalWidth)
        stackView.spacing = scale
        for item in items {
            item.setDisplayIconSize(iconWidth * scale)
        }
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        stackView.layoutSubtreeIfNeeded()
    }
    
    func reloadData() {
        lastFitWidth = nil
        lastFitNaturalWidth = nil
        items = applications.map { self.createAppButton(for: $0) }
        let stackView = NSStackView(views: items.compactMap { $0.view })
        stackView.spacing = 1
        stackView.orientation = .horizontal
        self.stackView = stackView
        let visibleRect = self.scrollView.documentVisibleRect
        scrollView.documentView = stackView
        stackView.scroll(visibleRect.origin)
    }

    public func createAppButton(for app: DockItem) -> DockBarItem {
        let item = DockBarItem(app)
        item.isBordered = false
        item.actions.append(contentsOf: [
            ItemAction(trigger: .singleTap) { [weak self] in
                self?.switchToApp(app: app)
            },
            ItemAction(trigger: .longTap) { [weak self] in
                self?.handleHalfLongPress(item: app)
            }
        ])
        item.killAppClosure = {[weak self] in
            self?.handleLongPress(item: app)
        }
        
        return item
    }
    
    public func switchToApp(app: DockItem) {
        let bundleIdentifier = app.bundleIdentifier
        if bundleIdentifier!.contains("file://") {
            NSWorkspace.shared.openFile(bundleIdentifier!.replacingOccurrences(of: "file://", with: ""))
        } else {
            NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleIdentifier!, options: [.default], additionalEventParamDescriptor: nil, launchIdentifier: nil)
        }
        softReloadItems()

        // NB: if you can't open app which on another space, try to check mark
        // "When switching to an application, switch to a Space with open windows for the application"
        // in Mission control settings
    }
    
    //todo
    private func handleLongPress(item: DockItem) {
        if let pid = item.pid, let app = NSRunningApplication(processIdentifier: pid) {
            if !app.terminate() {
                app.forceTerminate()
            }
            hardReloadItems()
        }
    }
    
    private func handleHalfLongPress(item: DockItem) {
        if let index = self.persistentAppIdentifiers.firstIndex(of: item.bundleIdentifier) {
            persistentAppIdentifiers.remove(at: index)
        } else {
            persistentAppIdentifiers.append(item.bundleIdentifier)
        }

        AppSettings.dockPersistentAppIds = persistentAppIdentifiers
        hardReloadItems()
    }
    
    public func getIcon(forBundleIdentifier bundleIdentifier: String? = nil, orPath path: String? = nil) -> NSImage {
        DockAppSnapshotSource.icon(forBundleIdentifier: bundleIdentifier, orPath: path)
    }
}

public class DockItem: NSObject {
    var bundleIdentifier: String!, name: String!, icon: NSImage!, pid: Int32!, running: Bool = false

    convenience init(bundleIdentifier: String, name: String? = nil, icon: NSImage, pid: Int32? = nil, running: Bool = false) {
        self.init()
        self.bundleIdentifier = bundleIdentifier
        self.name = name ?? bundleIdentifier
        self.icon = icon
        self.pid = pid
        self.running = running
    }
}

struct DockAppsSnapshot {
    let applications: [DockItem]
}

enum DockAppSnapshotSource {
    static func preferredWidth(appCount: Int, iconSize: CGFloat = iconWidth, spacing: CGFloat = 1) -> CGFloat {
        guard appCount > 0 else { return 0 }
        return CGFloat(appCount) * iconSize + CGFloat(appCount - 1) * spacing
    }

    static func load(filter: NSRegularExpression?, persistentIdentifiers: [String] = AppSettings.dockPersistentAppIds) -> DockAppsSnapshot {
        var runningIdentifiers: [String] = []
        var applications: [DockItem] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, let bundleIdentifier = app.bundleIdentifier else { continue }
            if let filter, let name = app.localizedName,
               filter.numberOfMatches(in: name, options: [], range: NSRange(location: 0, length: (name as NSString).length)) == 0 { continue }
            runningIdentifiers.append(bundleIdentifier)
            applications.append(DockItem(bundleIdentifier: bundleIdentifier, name: app.localizedName, icon: app.icon ?? icon(forBundleIdentifier: bundleIdentifier), pid: app.processIdentifier, running: true))
        }
        for bundleIdentifier in persistentIdentifiers where !runningIdentifiers.contains(bundleIdentifier) {
            let appPath = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleIdentifier)
            let name = appPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? bundleIdentifier
            applications.append(DockItem(bundleIdentifier: bundleIdentifier, name: name, icon: icon(forBundleIdentifier: bundleIdentifier), running: false))
        }
        return DockAppsSnapshot(applications: applications)
    }

    static func icon(forBundleIdentifier bundleIdentifier: String? = nil, orPath path: String? = nil) -> NSImage {
        if let bundleIdentifier, let appPath = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appPath)
        }
        if let path { return NSWorkspace.shared.icon(forFile: path) }
        let genericIcon = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns")
        return genericIcon ?? NSImage(size: .zero)
    }
}

final class DockPreviewSnapshotCache {
    static let shared = DockPreviewSnapshotCache()
    private let lock = NSLock()
    private let snapshotProvider: (String?, [String]) -> DockAppsSnapshot
    private var cachedKey: String?
    private var cachedResponse: [String: Any]?
    private var revision = 0

    init(snapshotProvider: @escaping (String?, [String]) -> DockAppsSnapshot = { filterPattern, persistentIdentifiers in
        let filter = filterPattern.flatMap { try? NSRegularExpression(pattern: $0) }
        return DockAppSnapshotSource.load(filter: filter, persistentIdentifiers: persistentIdentifiers)
    }) {
        self.snapshotProvider = snapshotProvider
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(invalidate), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(invalidate), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    @objc private func invalidate() {
        lock.lock()
        cachedKey = nil
        lock.unlock()
    }

    func response(filterPattern: String?, sinceRevision: String?, persistentIdentifiers: [String] = AppSettings.dockPersistentAppIds) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(filterPattern ?? "")|\(persistentIdentifiers.joined(separator: ","))"
        if key != cachedKey {
            let snapshot = snapshotProvider(filterPattern, persistentIdentifiers)
            let apps: [[String: Any]] = snapshot.applications.map { item in
                ["bundleId": item.bundleIdentifier ?? "", "name": item.name ?? item.bundleIdentifier ?? "", "running": item.running,
                 "iconData": Self.iconDataURL(item.icon)]
            }
            revision += 1
            let naturalWidth = DockAppSnapshotSource.preferredWidth(appCount: snapshot.applications.count)
            cachedResponse = ["success": true, "revision": String(revision), "unchanged": false,
                              "preferredWidth": naturalWidth, "iconSize": iconWidth, "itemSpacing": 1, "apps": apps]
            cachedKey = key
        }
        if let currentRevision = cachedResponse?["revision"] as? String, sinceRevision == currentRevision {
            return ["success": true, "revision": sinceRevision ?? "", "unchanged": true]
        }
        return cachedResponse ?? ["success": true, "revision": String(revision), "unchanged": false, "preferredWidth": 0, "iconSize": iconWidth, "itemSpacing": 1, "apps": []]
    }

    private static func iconDataURL(_ image: NSImage) -> String {
        let size = NSSize(width: 32, height: 32)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        thumb.unlockFocus()
        let data: Data
        if let tiff = thumb.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            data = bitmap.representation(using: .png, properties: [:]) ?? Data()
        } else {
            data = Data()
        }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }
}

class DockBarItem: CustomButtonTouchBarItem {
    let dotView = NSView(frame: .zero)
    let dockItem: DockItem
    fileprivate var killGestureRecognizer: LongPressGestureRecognizer!
    var killAppClosure: () -> Void = { }
    
    var isRunning = false {
        didSet {
            redrawDotView()
        }
    }
    
    var isFrontmost = false {
        didSet {
            redrawDotView()
        }
    }
    private var displayIconSize: CGFloat = iconWidth
    private var iconWidthConstraint: NSLayoutConstraint?
    
    init(_ app: DockItem) {
        self.dockItem = app
        super.init(identifier: .init(app.bundleIdentifier), title: "")
        dotView.wantsLayer = true
        
        image = app.icon
        image?.size = NSSize(width: iconWidth, height: iconWidth)

        killGestureRecognizer = LongPressGestureRecognizer(target: self, action: #selector(firePanGestureRecognizer))
        killGestureRecognizer.allowedTouchTypes = .direct
        killGestureRecognizer.recognizeTimeout = 1.5
        killGestureRecognizer.minimumPressDuration = 1.5
        killGestureRecognizer.isEnabled = isRunning
        
        self.finishViewConfiguration = { [weak self] in
            guard let selfie = self else { return }
            selfie.dotView.layer?.cornerRadius = 1.5
            selfie.view.addSubview(selfie.dotView)
            selfie.redrawDotView()
            selfie.view.addGestureRecognizer(selfie.killGestureRecognizer)
        }
    }
    
    func redrawDotView() {
        dotView.layer?.backgroundColor = isRunning ? NSColor.white.cgColor : NSColor.clear.cgColor
        dotView.frame.size = NSSize(width: isFrontmost ? max(3, displayIconSize - 14) : 3, height: 3)
        dotView.setFrameOrigin(NSPoint(x: displayIconSize / 2 - dotView.frame.size.width / 2, y: displayIconSize - 5))
    }

    func setDisplayIconSize(_ size: CGFloat) {
        if let iconWidthConstraint, abs(iconWidthConstraint.constant - size) < 0.001 { return }
        displayIconSize = size
        image?.size = NSSize(width: size, height: size)
        if let iconWidthConstraint {
            iconWidthConstraint.constant = size
        } else {
            let constraint = view.widthAnchor.constraint(equalToConstant: size)
            constraint.isActive = true
            iconWidthConstraint = constraint
        }
        view.invalidateIntrinsicContentSize()
        redrawDotView()
    }
    
    @objc func firePanGestureRecognizer() {
        self.killAppClosure()
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
