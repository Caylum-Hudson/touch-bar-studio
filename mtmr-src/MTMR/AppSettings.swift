import Foundation

struct AppSettings {
    @UserDefault(key: "nz.caylum.touchbarstudio.touchBarEnabled", defaultValue: true)
    static var touchBarEnabled: Bool

    @UserDefault(key: "com.toxblh.mtmr.settings.showControlStrip", defaultValue: false)
    static var showControlStripState: Bool

    /// Native Control Strip preservation uses the compact custom modal. An
    /// expanded native volume or brightness slider temporarily takes the
    /// full bar and returns to this preference when dismissed.
    static func shouldUseCompactControlStripPresentation(keepControlStrip: Bool, sliderExpanded: Bool) -> Bool {
        return keepControlStrip && !sliderExpanded
    }
    
    @UserDefault(key: "com.toxblh.mtmr.settings.hapticFeedback", defaultValue: true)
    static var hapticFeedbackState: Bool
    
    @UserDefault(key: "com.toxblh.mtmr.settings.multitouchGestures", defaultValue: true)
    static var multitouchGestures: Bool
    
    @UserDefault(key: "com.toxblh.mtmr.blackListedApps", defaultValue: [])
    static var blacklistedAppIds: [String]
    
    @UserDefault(key: "com.toxblh.mtmr.dock.persistent", defaultValue: [])
    static var dockPersistentAppIds: [String]
}

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    var wrappedValue: T {
        get {
            return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            UserDefaults.standard.synchronize()
        }
    }
}
