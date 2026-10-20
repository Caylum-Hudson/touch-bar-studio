//
//  TouchBar.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

struct ExactItem {
    let identifier: NSTouchBarItem.Identifier
    let presetItem: BarItemDefinition
}

let appSupportDirectory = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR")
let standardConfigPath = appSupportDirectory.appending("/items.json")

extension ItemType {
    var identifierBase: String {
        switch self {
        case .staticButton(title: _):
            return "com.toxblh.mtmr.staticButton."
        case .appleScriptTitledButton(source: _):
            return "com.toxblh.mtmr.appleScriptButton."
        case .shellScriptTitledButton(source: _):
            return "com.toxblh.mtmr.shellScriptButton."
        case .timeButton(formatTemplate: _, timeZone: _, locale: _):
            return "com.toxblh.mtmr.timeButton."
        case .battery:
            return "com.toxblh.mtmr.battery."
        case .cpu(refreshInterval: _):
            return "com.toxblh.mtmr.cpu."
        case .dock(autoResize: _, filter: _):
            return "com.toxblh.mtmr.dock"
        case .volume:
            return "com.toxblh.mtmr.volume"
        case .brightness(refreshInterval: _):
            return "com.toxblh.mtmr.brightness"
        case .weather(interval: _, units: _, api_key: _, icon_type: _):
            return "com.toxblh.mtmr.weather"
        case .yandexWeather(interval: _):
            return "com.toxblh.mtmr.yandexWeather"
        case .currency(interval: _, from: _, to: _, full: _):
            return "com.toxblh.mtmr.currency"
        case .inputsource:
            return "com.toxblh.mtmr.inputsource."
        case .music(interval: _):
            return "com.toxblh.mtmr.music."
        case .group(items: _):
            return "com.toxblh.mtmr.groupBar."
        case .nightShift:
            return "com.toxblh.mtmr.nightShift."
        case .dnd:
            return "com.toxblh.mtmr.dnd."
        case .pomodoro(interval: _):
            return PomodoroBarItem.identifier
        case .network(flip: _):
            return NetworkBarItem.identifier
        case .darkMode:
            return DarkModeBarItem.identifier
        case .swipe(direction: _, fingers: _, minOffset: _, sourceApple: _, sourceBash: _):
            return "com.toxblh.mtmr.swipe."
        case .upnext(from: _, to: _, maxToShow: _, autoResize: _):
            return "com.connorgmeehan.mtmrup.next."
        }
    }
}

extension NSTouchBarItem.Identifier {
    static let controlStripItem = NSTouchBarItem.Identifier("com.toxblh.mtmr.controlStrip")
}

class TouchBarController: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarController()

    var touchBar: NSTouchBar!

    fileprivate var lastPresetPath = ""
    var jsonItems: [BarItemDefinition] = []
    var navigationStack: [[BarItemDefinition]] = []
    func enterSubmenu(_ items: [BarItemDefinition]) {
        guard AppSettings.touchBarEnabled else { return }
        navigationStack.append(jsonItems)
        let back = BarItemDefinition(type: .staticButton(title: "‹ Back"), actions: [Action(trigger:.singleTap,value:.custom(closure:{ [weak self] in self?.leaveSubmenu() }))], action:.none, legacyLongAction:.none, additionalParameters:[.align:.align(.left),.width:.width(54)])
        createAndUpdatePreset(newJsonItems:[back] + items)
    }
    func leaveSubmenu() {
        if let previous = navigationStack.popLast() { createAndUpdatePreset(newJsonItems:previous) }
    }
    var itemDefinitions: [NSTouchBarItem.Identifier: BarItemDefinition] = [:]
    var items: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    var leftIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerIdentifiers: [NSTouchBarItem.Identifier] = []
    var rightIdentifiers: [NSTouchBarItem.Identifier] = []
    var basicViewIdentifier = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollView.".appending(UUID().uuidString))
    var basicView: BasicView?
    var swipeItems: [SwipeItem] = []
    private var expandedNativeSliderItem: NSTouchBarItem?
    private var expandedNativeSliderController: NSCustomTouchBarItem?
    private var barBeforeExpandedNativeSlider: NSTouchBar?
    var expandedBrightnessStatus: String? {
        (expandedNativeSliderController as? BrightnessViewController)?.lastBrightnessStatus
    }

    var blacklistAppIdentifiers: [String] = []
    var frontmostApplicationIdentifier: String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private override init() {
        super.init()
        Self.registerNavigationControls(dismiss: { [weak self] in self?.dismissTouchBar() }, back: { [weak self] in self?.leaveSubmenu() })

        blacklistAppIdentifiers = AppSettings.blacklistedAppIds

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        reloadStandardConfig()
    }

    static func registerNavigationControls(dismiss: @escaping () -> Void, back: @escaping () -> Void) {
        SupportedTypesHolder.sharedInstance.register(
            typename: "exitTouchbar",
            item: .staticButton(title: "exit"),
            actions: [
                Action(trigger: .singleTap, value: .custom(closure: dismiss))
            ],
            legacyAction: .none,
            legacyLongAction: .none
        )

        SupportedTypesHolder.sharedInstance.register(typename: "close") { _ in
            (
                item: .staticButton(title: ""),
                actions: [
                    Action(trigger: .singleTap, value: .custom(closure: back))
                ],
                legacyAction: .none,
                legacyLongAction: .none,
                parameters: [.width: .width(30), .image: .image(source: (NSImage(named: NSImage.stopProgressFreestandingTemplateName))!)])
        }

    }

    func createAndUpdatePreset(newJsonItems: [BarItemDefinition]) {
        cancelExpandedNativeSlider(restorePreviousBar: false)
        if let oldBar = self.touchBar {
            minimizeSystemModal(oldBar)
        }
        touchBar = NSTouchBar()
        jsonItems = newJsonItems
        itemDefinitions = [:]
        leftIdentifiers = []
        centerIdentifiers = []
        rightIdentifiers = []

        loadItemDefinitions(jsonItems: jsonItems)
        
        updateActiveApp()
    }
    
    func didItemsChange(prevItems: [NSTouchBarItem.Identifier: NSTouchBarItem], prevSwipeItems: [SwipeItem]) -> Bool {
        var changed = items.count != prevItems.count || swipeItems.count != prevSwipeItems.count
        
        if !changed {
            for (item, prevItem) in zip(items, prevItems) {
                if item.key != prevItem.key {
                    changed = true
                    break
                }
            }
        }

        if !changed {
            for (swipeItem, prevSwipeItem) in zip(swipeItems, prevSwipeItems) {
                if !swipeItem.isEqual(prevSwipeItem) {
                    changed = true
                    break
                }
            }
        }

        return changed
    }
    
    func prepareTouchBar() {
        let prevItems = items
        let prevSwipeItems = swipeItems

        createItems()

        let changed = didItemsChange(prevItems: prevItems, prevSwipeItems: prevSwipeItems)

        if !changed {
            return
        }
        
        let centerItems = centerIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })

        let centerScrollArea = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollArea.".appending(UUID().uuidString))
        let scrollArea = ScrollViewItem(identifier: centerScrollArea, items: centerItems)
        
        basicViewIdentifier = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollView.".appending(UUID().uuidString))

        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [basicViewIdentifier]

        let leftItems = leftIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })
        let rightItems = rightIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })

        basicView = BasicView(identifier: basicViewIdentifier, items:leftItems + [scrollArea] + rightItems, swipeItems: swipeItems)
        let orderedIdentifiers = leftIdentifiers + centerIdentifiers + rightIdentifiers
        let visibleIdentifiers = orderedIdentifiers.filter { items[$0] != nil }
        let definitions = visibleIdentifiers.compactMap { itemDefinitions[$0] }
        if StudioLayout.precise(definitions) {
            basicView = BasicView(identifier:basicViewIdentifier,items:visibleIdentifiers.compactMap { items[$0] },swipeItems:swipeItems,frames:preciseFrames(definitions))
        }
        basicView?.legacyGesturesEnabled = AppSettings.multitouchGestures
    }

    func preciseFrames(_ definitions:[BarItemDefinition]) -> [CGRect] {
        if !navigationStack.isEmpty && !definitions.isEmpty {
            let scale = (StudioLayout.width-62)/StudioLayout.width
            let children = StudioLayout.frames(Array(definitions.dropFirst())).map { frame in
                CGRect(x:62+frame.minX*scale,y:0,width:frame.width*scale,height:30)
            }
            return [CGRect(x:0,y:0,width:54,height:30)] + children
        }
        return StudioLayout.frames(definitions)
    }

    @objc func activeApplicationChanged(_: Notification) {
        cancelExpandedNativeSlider(restorePreviousBar: false)
        if let items = StudioStore.shared.selectedItems(bundle: frontmostApplicationIdentifier) {
            navigationStack = []
            createAndUpdatePreset(newJsonItems:items)
            return
        }
        updateActiveApp()
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { cancelExpandedNativeSlider(restorePreviousBar: false) }
        AppSettings.touchBarEnabled = enabled
        navigationStack = []
        DFRSystemModalShowsCloseBoxWhenFrontMost(!enabled)
        if enabled {
            reloadStandardConfig()
        } else if let bar = touchBar {
            NSTouchBar.dismissSystemModalTouchBar(bar)
        }
        updateControlStripPresence()
        (NSApp.delegate as? AppDelegate)?.createMenu()
    }

    func updateActiveApp() {
        guard AppSettings.touchBarEnabled else {
            if let bar = touchBar { NSTouchBar.dismissSystemModalTouchBar(bar) }
            updateControlStripPresence()
            return
        }
        if frontmostApplicationIdentifier != nil && blacklistAppIdentifiers.firstIndex(of: frontmostApplicationIdentifier!) != nil {
            dismissTouchBar()
        } else {
            prepareTouchBar()
            if touchBarContainsAnyItems() {
                presentTouchBar()
            } else {
                dismissTouchBar()
            }
        }
    }
    
    func touchBarContainsAnyItems() -> Bool {
        return items.count != 0 || swipeItems.count != 0
    }

    func reloadStandardConfig() {
        if let items = StudioStore.shared.selectedItems(bundle:frontmostApplicationIdentifier) {
            createAndUpdatePreset(newJsonItems:items)
            return
        }
        let presetPath = standardConfigPath
        if !FileManager.default.fileExists(atPath: presetPath) {
            try? FileManager.default.createDirectory(atPath: appSupportDirectory, withIntermediateDirectories: true, attributes: nil)
            if let defaultPreset = Bundle.main.path(forResource: "defaultPreset", ofType: "json") {
                try? FileManager.default.copyItem(atPath: defaultPreset, toPath: presetPath)
            } else if !FileManager.default.fileExists(atPath: presetPath) {
                try? "[]".write(toFile: presetPath, atomically: true, encoding: .utf8)
            }
        }

        reloadPreset(path: presetPath)
    }

    func reloadPreset(path: String) {
        lastPresetPath = path
        let items = path.fileData?.barItemDefinitions() ?? [BarItemDefinition(type: .staticButton(title: "bad preset"), actions: [], action: .none, legacyLongAction: .none, additionalParameters: [:])]
        createAndUpdatePreset(newJsonItems: items)
    }

    func loadItemDefinitions(jsonItems: [BarItemDefinition]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH-mm-ss"
        let time = dateFormatter.string(from: Date())
        for item in jsonItems {
            let identifierString = item.type.identifierBase.appending(time + "--" + UUID().uuidString)
            let identifier = NSTouchBarItem.Identifier(identifierString)
            itemDefinitions[identifier] = item
            if item.align == .left {
                leftIdentifiers.append(identifier)
            }
            if item.align == .right {
                rightIdentifiers.append(identifier)
            }
            if item.align == .center {
                centerIdentifiers.append(identifier)
            }
        }
    }

    func createItems() {
        items = [:]
        swipeItems = []

        for (identifier, definition) in itemDefinitions {
            var show = true
            
            if let frontApp = frontmostApplicationIdentifier {
                if case let .matchAppId(regexString)? = definition.additionalParameters[.matchAppId] {
                    guard let regex = try? NSRegularExpression(pattern: regexString) else { continue }
                    let range = NSRange(location: 0, length: frontApp.count)
                    if regex.firstMatch(in: frontApp, range: range) == nil {
                        show = false
                    }
                }
            }
            
            if show {
                let item = createItem(forIdentifier: identifier, definition: definition)
                if item is SwipeItem {
                    swipeItems.append(item as! SwipeItem)
                } else {
                    items[identifier] = item
                }
            }
        }
    }

    @objc func setupControlStripPresence() {
        DFRSystemModalShowsCloseBoxWhenFrontMost(!AppSettings.touchBarEnabled)
        let item = NSCustomTouchBarItem(identifier: .controlStripItem)
        item.view = NSButton(image: #imageLiteral(resourceName: "StatusImage"), target: self, action: #selector(presentTouchBar))
        NSTouchBarItem.addSystemTrayItem(item)
        updateControlStripPresence()
    }

    func updateControlStripPresence() {
        let showMtmrButtonOnControlStrip = AppSettings.touchBarEnabled && touchBarContainsAnyItems()
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, showMtmrButtonOnControlStrip)
    }

    @objc private func presentTouchBar() {
        guard AppSettings.touchBarEnabled else { return }
        if AppSettings.showControlStripState && expandedNativeSliderItem == nil {
            presentSystemModal(touchBar, systemTrayItemIdentifier: .controlStripItem)
        } else {
            presentSystemModal(touchBar, placement: 1, systemTrayItemIdentifier: .controlStripItem)
        }
        updateControlStripPresence()
    }

    @objc private func dismissTouchBar() {
        if touchBarContainsAnyItems() {
            minimizeSystemModal(touchBar)
        }
        updateControlStripPresence()
    }

    @objc func resetControlStrip() {
        dismissTouchBar()
        updateActiveApp()
    }

    func touchBar(_: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if let expandedNativeSliderItem, expandedNativeSliderItem.identifier == identifier {
            return expandedNativeSliderItem
        }
        if identifier == basicViewIdentifier {
            return basicView
        }

        return nil
    }

    func createItem(forIdentifier identifier: NSTouchBarItem.Identifier, definition item: BarItemDefinition) -> NSTouchBarItem? {
        var barItem: NSTouchBarItem!
        switch item.type {
        case let .staticButton(title: title):
            barItem = CustomButtonTouchBarItem(identifier: identifier, title: title)
        case let .appleScriptTitledButton(source: source, refreshInterval: interval, alternativeImages: alternativeImages):
            barItem = CustomButtonTouchBarItem(identifier:identifier,title:"Script disabled")
        case let .shellScriptTitledButton(source: source, refreshInterval: interval):
            barItem = CustomButtonTouchBarItem(identifier:identifier,title:"Script disabled")
        case let .timeButton(formatTemplate: template, timeZone: timeZone, locale: locale):
            barItem = TimeTouchBarItem(identifier: identifier, formatTemplate: template, timeZone: timeZone, locale: locale)
        case .battery:
            barItem = BatteryBarItem(identifier: identifier)
        case let .cpu(refreshInterval: refreshInterval):
            barItem = CPUBarItem(identifier: identifier, refreshInterval: refreshInterval)
        case let .dock(autoResize: autoResize, filter: regexString):
            if let regexString = regexString {
                guard let regex = try? NSRegularExpression(pattern: regexString, options: []) else {
                    barItem = CustomButtonTouchBarItem(identifier: identifier, title: "Bad regex: '\(regexString)'")
                    break
                }
                barItem = AppScrubberTouchBarItem(identifier: identifier, autoResize: autoResize, filter: regex)
            } else {
                barItem = AppScrubberTouchBarItem(identifier: identifier, autoResize: autoResize)
            }
        case .volume:
            let button = CustomButtonTouchBarItem(identifier: identifier, title: "")
            button.image = item.additionalParameters[.image].flatMap { parameter in
                if case let .image(source) = parameter { return source.image }
                return nil
            } ?? sliderEntrySymbol("speaker.wave.2.fill", label: "Volume")
            button.actions.append(ItemAction(trigger: .singleTap) { [weak self] in
                self?.presentExpandedNativeSlider(kind: .volume)
            })
            barItem = button
        case let .brightness(refreshInterval: interval):
            let button = CustomButtonTouchBarItem(identifier: identifier, title: "")
            button.image = item.additionalParameters[.image].flatMap { parameter in
                if case let .image(source) = parameter { return source.image }
                return nil
            } ?? sliderEntrySymbol("sun.max.fill", label: "Brightness")
            button.actions.append(ItemAction(trigger: .singleTap) { [weak self] in
                self?.presentExpandedNativeSlider(kind: .brightness(refreshInterval: interval))
            })
            barItem = button
        case let .weather(interval: interval, units: units, api_key: api_key, icon_type: icon_type):
            barItem = WeatherBarItem(identifier: identifier, interval: interval, units: units, api_key: api_key, icon_type: icon_type)
        case let .yandexWeather(interval: interval):
            barItem = YandexWeatherBarItem(identifier: identifier, interval: interval)
        case let .currency(interval: interval, from: from, to: to, full: full):
            barItem = CurrencyBarItem(identifier: identifier, interval: interval, from: from, to: to, full: full)
        case .inputsource:
            barItem = InputSourceBarItem(identifier: identifier)
        case let .music(interval: interval, disableMarquee: disableMarquee):
            barItem = MusicBarItem(identifier: identifier, interval: interval, disableMarquee: disableMarquee)
        case let .group(items: items):
            barItem = GroupBarItem(identifier: identifier, items: items)
        case .nightShift:
            barItem = NightShiftBarItem(identifier: identifier)
        case .dnd:
            barItem = DnDBarItem(identifier: identifier)
        case let .pomodoro(workTime: workTime, restTime: restTime):
            barItem = PomodoroBarItem(identifier: identifier, workTime: workTime, restTime: restTime)
        case let .network(flip: flip, units: units):
            barItem = NetworkBarItem(identifier: identifier, flip: flip, units: units)
        case .darkMode:
            barItem = DarkModeBarItem(identifier: identifier)
        case let .swipe(direction: direction, fingers: fingers, minOffset: minOffset, sourceApple: sourceApple, sourceBash: sourceBash):
            barItem = CustomButtonTouchBarItem(identifier:identifier,title:"Script disabled")
        case let .upnext(from: from, to: to, maxToShow: maxToShow, autoResize: autoResize):
            barItem = UpNextScrubberTouchBarItem(identifier: identifier, interval: 60, from: from, to: to, maxToShow: maxToShow, autoResize: autoResize)
        }

        if let action = self.action(forItem: item), let item = barItem as? CustomButtonTouchBarItem {
            item.actions.append(ItemAction(trigger: .singleTap, action))
        }
        if let longAction = self.longAction(forItem: item), let item = barItem as? CustomButtonTouchBarItem {
            item.actions.append(ItemAction(trigger: .longTap, longAction))
        }
        
        if let touchBarItem = barItem as? CustomButtonTouchBarItem {
            for action in item.actions {
                touchBarItem.actions.append(ItemAction(trigger: action.trigger, self.closure(for: action)))
            }
        }
        if case let .bordered(bordered)? = item.additionalParameters[.bordered], let item = barItem as? CustomButtonTouchBarItem {
            item.isBordered = bordered
        }
        if case let .background(color)? = item.additionalParameters[.background], let item = barItem as? CustomButtonTouchBarItem {
            item.backgroundColor = color
        }
        if case let .width(value)? = item.additionalParameters[.width], let widthBarItem = barItem as? CanSetWidth {
            widthBarItem.setWidth(value: value)
        }
        if case let .image(source)? = item.additionalParameters[.image], let item = barItem as? CustomButtonTouchBarItem {
            item.image = source.image
        }
        if case let .title(value)? = item.additionalParameters[.title] {
            if let item = barItem as? GroupBarItem {
                item.collapsedRepresentationLabel = value
            } else if let item = barItem as? CustomButtonTouchBarItem {
                item.title = value
            }
        }
        return barItem
    }
    
    func closure(for action: Action) -> (() -> Void)? {
        switch action.value {
        case let .hidKey(keycode: keycode):
            return { HIDPostAuxKey(keycode) }
        case let .keyPress(keycode: keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case .appleScript:
            return nil
        case .shellScript:
            return nil
        case let .openUrl(url: url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                        print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case let .custom(closure: closure):
            return closure
        case .none:
            return nil
        }
    }

    private enum ExpandedSliderKind {
        case volume
        case brightness(refreshInterval: Double)
    }

    private func presentExpandedNativeSlider(kind: ExpandedSliderKind) {
        guard AppSettings.touchBarEnabled, expandedNativeSliderItem == nil, let currentBar = touchBar else { return }
        let identifier = NSTouchBarItem.Identifier("com.toxblh.mtmr.expandedSlider.\(UUID().uuidString)")
        let sliderController: NSCustomTouchBarItem
        let minimumSymbol: String
        let maximumSymbol: String
        switch kind {
        case .volume:
            sliderController = VolumeViewController(identifier: identifier)
            minimumSymbol = "speaker.fill"
            maximumSymbol = "speaker.wave.3.fill"
        case let .brightness(refreshInterval):
            sliderController = BrightnessViewController(identifier: identifier, refreshInterval: refreshInterval)
            minimumSymbol = "sun.min.fill"
            maximumSymbol = "sun.max.fill"
        }

        let expandedItem = ExpandedNativeSliderTouchBarItem(
            identifier: identifier,
            slider: sliderController.view,
            minimumSymbol: minimumSymbol,
            maximumSymbol: maximumSymbol,
            onBack: { [weak self] in self?.cancelExpandedNativeSlider(restorePreviousBar: true) }
        )
        expandedNativeSliderItem = expandedItem
        expandedNativeSliderController = sliderController
        barBeforeExpandedNativeSlider = currentBar
        minimizeSystemModal(currentBar)

        let expandedBar = NSTouchBar()
        expandedBar.delegate = self
        expandedBar.defaultItemIdentifiers = [identifier]
        touchBar = expandedBar
        presentTouchBar()
    }

    private func sliderEntrySymbol(_ name: String, label: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        )
    }

    private func cancelExpandedNativeSlider(restorePreviousBar: Bool) {
        guard expandedNativeSliderItem != nil else { return }
        if let activeBar = touchBar { minimizeSystemModal(activeBar) }
        let previousBar = barBeforeExpandedNativeSlider
        expandedNativeSliderItem = nil
        expandedNativeSliderController = nil
        barBeforeExpandedNativeSlider = nil
        if restorePreviousBar, let previousBar {
            touchBar = previousBar
            presentTouchBar()
        } else if let previousBar {
            touchBar = previousBar
        }
    }

    func action(forItem item: BarItemDefinition) -> (() -> Void)? {
        switch item.legacyAction {
        case let .hidKey(keycode: keycode):
            return { HIDPostAuxKey(keycode) }
        case let .keyPress(keycode: keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case .appleScript:
            return nil
        case .shellScript:
            return nil
        case let .openUrl(url: url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                        print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case let .custom(closure: closure):
            return closure
        case .none:
            return nil
        }
    }

    func longAction(forItem item: BarItemDefinition) -> (() -> Void)? {
        switch item.legacyLongAction {
        case let .hidKey(keycode: keycode):
            return { HIDPostAuxKey(keycode) }
        case let .keyPress(keycode: keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case .appleScript:
            return nil
        case .shellScript:
            return nil
        case let .openUrl(url: url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                        print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case let .custom(closure: closure):
            return closure
        case .none:
            return nil
        }
    }
}

protocol CanSetWidth {
    func setWidth(value: CGFloat)
}

extension NSCustomTouchBarItem: CanSetWidth {
    func setWidth(value: CGFloat) {
        view.widthAnchor.constraint(equalToConstant: value).isActive = true
    }
}

extension NSPopoverTouchBarItem: CanSetWidth {
    func setWidth(value: CGFloat) {
        view?.widthAnchor.constraint(equalToConstant: value).isActive = true
    }
}

extension BarItemDefinition {
    var align: Align {
        if case let .align(result)? = additionalParameters[.align] {
            return result
        }
        return .center
    }
}

final class ExpandedNativeSliderTouchBarItem: NSCustomTouchBarItem {
    private let onBack: () -> Void
    private(set) var backButton: NSButton!
    private(set) var sliderRow: NSStackView!

    init(identifier: NSTouchBarItem.Identifier, slider: NSView?, minimumSymbol: String, maximumSymbol: String, onBack: @escaping () -> Void) {
        self.onBack = onBack
        super.init(identifier: identifier)

        backButton = NSButton(title: "Back", target: self, action: #selector(goBack))
        backButton.bezelStyle = .rounded
        backButton.setAccessibilityLabel("Back to Touch Bar")

        let minimum = endpointView(symbol: minimumSymbol, label: "Minimum")
        let maximum = endpointView(symbol: maximumSymbol, label: "Maximum")
        let slider = slider ?? NSSlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 340).isActive = true

        sliderRow = NSStackView(views: [minimum, slider, maximum])
        sliderRow.orientation = .horizontal
        sliderRow.alignment = .centerY
        sliderRow.distribution = .fill
        sliderRow.spacing = 14
        sliderRow.translatesAutoresizingMaskIntoConstraints = false

        // Give the centered slider its own column, with Back anchored at the
        // leading edge of the full-width Touch Bar item.
        let fullWidthView = NSView(frame: CGRect(x: 0, y: 0, width: StudioLayout.width, height: 30))
        backButton.translatesAutoresizingMaskIntoConstraints = false
        sliderRow.translatesAutoresizingMaskIntoConstraints = false
        fullWidthView.addSubview(backButton)
        fullWidthView.addSubview(sliderRow)
        let preferredWidth = fullWidthView.widthAnchor.constraint(equalToConstant: StudioLayout.width)
        preferredWidth.priority = .defaultLow
        NSLayoutConstraint.activate([
            preferredWidth,
            fullWidthView.heightAnchor.constraint(equalToConstant: 30),
            backButton.leadingAnchor.constraint(equalTo: fullWidthView.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: fullWidthView.centerYAnchor),
            sliderRow.centerXAnchor.constraint(equalTo: fullWidthView.centerXAnchor),
            sliderRow.centerYAnchor.constraint(equalTo: fullWidthView.centerYAnchor)
        ])
        view = fullWidthView
    }

    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func endpointView(symbol: String, label: String) -> NSImageView {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        ) ?? NSImage()
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setAccessibilityLabel(label)
        imageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return imageView
    }

    @objc private func goBack() { onBack() }
}
