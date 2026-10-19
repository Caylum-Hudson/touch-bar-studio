import Cocoa
import Carbon

final class StudioLauncher {
    static let shared = StudioLauncher()
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    func configure() {
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { StudioLauncher.shared.open() }
                return noErr
            }, 1, &event, nil, &handler)
        }
        if let key = hotKey { UnregisterEventHotKey(key) }
        let settings = StudioStore.shared.workspace["settings"] as? [String:Any] ?? [:]
        let modifiers = settings["shortcut"] as? String == "commandShift" ? UInt32(cmdKey | shiftKey) : UInt32(controlKey | optionKey)
        RegisterEventHotKey(UInt32(kVK_Space), modifiers, EventHotKeyID(signature:0x53545544,id:1), GetApplicationEventTarget(), 0, &hotKey)
    }
    @objc func open() {
        DesignerWindowController.launcher.showWindow()
    }
}
