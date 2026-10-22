//
//  KeyPress.swift
//  MTMR
//
//  Created by Anton Palgunov on 17/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

protocol KeyPress {
    var keyCode: CGKeyCode { get }
    var modifiers: [String] { get }
    func send()
}

extension KeyPress {
    var modifiers: [String] { [] }
}

struct GenericKeyPress: KeyPress {
    var keyCode: CGKeyCode
    var modifiers: [String] = []

    static func eventFlags(for modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains("command") { flags.insert(.maskCommand) }
        if modifiers.contains("option") { flags.insert(.maskAlternate) }
        if modifiers.contains("shift") { flags.insert(.maskShift) }
        if modifiers.contains("control") { flags.insert(.maskControl) }
        return flags
    }
}

extension KeyPress {
    func send() {
        StudioPermissions.performKeyboardAction {
            let src = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
            let flags = GenericKeyPress.eventFlags(for: modifiers)
            keyDown?.flags = flags
            keyUp?.flags = flags

            let loc: CGEventTapLocation = .cghidEventTap
            keyDown?.post(tap: loc)
            keyUp?.post(tap: loc)
        }
    }
}

func HIDPostAuxKey(_ key: Int32) {
    let key = UInt8(key)
    StudioPermissions.performKeyboardAction { MediaKeys.hidPostAuxKey(key) }
}
