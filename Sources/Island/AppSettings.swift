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
    static let statuslineTeeEnabledKey = "statuslineTeeEnabled"
    static let menuBarIconEnabledKey = "menuBarIconEnabled"
    static let answerFromIslandEnabledKey = "answerFromIslandEnabled"
    static let answerFromIslandOnboardingPromptedKey = "answerFromIslandOnboardingPrompted"
    static let lastNotifiedUpdateVersionKey = "lastNotifiedUpdateVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Self.borderEnabledKey: true,
            Self.soundEnabledKey: true,
            Self.hooksInstallAttemptedKey: false,
            // Quotas via the statusline tee (issue #9): opt-in, OFF by
            // default — the app never touches the user's statusline script
            // without an explicit menu action.
            Self.statuslineTeeEnabledKey: false,
            // Icône animée (issue #54): the menu-bar mascot is shown by
            // default. Turned off, the status item falls back to a static
            // neutral icon; the menu stays reachable either way.
            Self.menuBarIconEnabledKey: true,
            // Réponse depuis l'Island (issue #28): ON by default — it is the
            // value of the feature (PRD #23 US9 left it open; implementation
            // settles on on). Turned off, the option buttons still show but a
            // tap only degrades to display + focus, never injecting.
            Self.answerFromIslandEnabledKey: true,
            // Onboarding guidance (issue #28, US8) is shown once: the flag flips
            // the first time the feature is used without the Accessibility
            // permission, so System Settings never opens on every attempt.
            Self.answerFromIslandOnboardingPromptedKey: false,
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

    var statuslineTeeEnabled: Bool {
        get { defaults.bool(forKey: Self.statuslineTeeEnabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.statuslineTeeEnabledKey) }
    }

    var menuBarIconEnabled: Bool {
        get { defaults.bool(forKey: Self.menuBarIconEnabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.menuBarIconEnabledKey) }
    }

    var answerFromIslandEnabled: Bool {
        get { defaults.bool(forKey: Self.answerFromIslandEnabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.answerFromIslandEnabledKey) }
    }

    var answerFromIslandOnboardingPrompted: Bool {
        get { defaults.bool(forKey: Self.answerFromIslandOnboardingPromptedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.answerFromIslandOnboardingPromptedKey) }
    }

    /// Mise à jour (issue #91): the last version a macOS notification was
    /// posted for — one notification per version, ever (ADR-0010). Read by
    /// the caller of `UpdateCheckGate` and written by the notification
    /// handler AFTER the post, never by the pure gate. Nil until the first
    /// notified update (no `register` default needed).
    var lastNotifiedUpdateVersion: String? {
        get { defaults.string(forKey: Self.lastNotifiedUpdateVersionKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.lastNotifiedUpdateVersionKey) }
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
