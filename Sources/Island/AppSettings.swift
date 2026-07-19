import Foundation
import ServiceManagement

/// Persisted app preferences (UserDefaults). Border (Liseré) and sound are
/// plain stored settings for now — the features that consume them arrive in
/// wave 3. `hooksInstallAttempted` makes the hook installation a true
/// first-launch step: uninstalling from the menu is never silently undone at
/// the next launch.
@MainActor
struct AppSettings {
    static let borderEnabledKey = "borderEnabled"
    static let soundEnabledKey = "soundEnabled"
    static let hooksInstallAttemptedKey = "hooksInstallAttempted"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Self.borderEnabledKey: true,
            Self.soundEnabledKey: true,
            Self.hooksInstallAttemptedKey: false,
        ])
    }

    var borderEnabled: Bool {
        get { defaults.bool(forKey: Self.borderEnabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.borderEnabledKey) }
    }

    var soundEnabled: Bool {
        get { defaults.bool(forKey: Self.soundEnabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.soundEnabledKey) }
    }

    var hooksInstallAttempted: Bool {
        get { defaults.bool(forKey: Self.hooksInstallAttemptedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.hooksInstallAttemptedKey) }
    }
}

/// Login item via SMAppService (macOS 13+, no deprecated APIs). Registration
/// requires a real .app bundle: when running the bare SwiftPM binary it fails —
/// tolerated with a trace, never blocking.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true when the change took effect.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            print("island: login item \(enabled ? "registered" : "unregistered")")
            return true
        } catch {
            print("island: login item \(enabled ? "registration" : "unregistration") unavailable: \(error.localizedDescription)")
            return false
        }
    }
}
