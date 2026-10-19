import Cocoa
import ApplicationServices

/// Check permission silently. Opening settings is always an explicit user action.
enum StudioPermissions {
    static var keyboardAccess: Bool { AXIsProcessTrusted() }

    static func openSettings() -> Bool {
        guard let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Never synthesize input while macOS considers this build untrusted.
    @discardableResult
    static func performKeyboardAction(isTrusted: () -> Bool = { AXIsProcessTrusted() }, _ action: () -> Void) -> Bool {
        guard isTrusted() else { return false }
        action()
        return true
    }
}
