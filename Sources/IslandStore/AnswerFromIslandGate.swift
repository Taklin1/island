/// What a tap on an `AskUserQuestion` option button should do, once the
/// preference and the Accessibility permission are taken into account
/// (issue #28). The injection of #27 consults this gate before posting any
/// keystroke; #26 already renders the buttons regardless.
public enum AnswerFromIslandAction: Equatable, Sendable {
    /// Feature on *and* permission granted: proceed to targeting/injection
    /// (#27). The unicity guard of the spike still decides certain-or-focus.
    case inject
    /// Degrade to display + Click-to-focus (US9/US10, ADR-0009). Never blocks.
    /// `guideToSettings` is true only on the first no-permission use, so the
    /// caller opens System Settings once (onboarding, US8) and never nags.
    case displayAndFocus(guideToSettings: Bool)
}

/// The gate for "Réponse depuis l'Island" (issue #28): a pure decision over the
/// on/off preference and the Accessibility permission. Kept free of AppKit so it
/// stays testable without touching the real TCC database — the caller supplies
/// the two booleans (preference from `AppSettings`, permission from
/// `AccessibilityPermission`).
public enum AnswerFromIslandGate {
    public static func action(
        featureEnabled: Bool,
        permissionGranted: Bool,
        onboardingAlreadyPrompted: Bool
    ) -> AnswerFromIslandAction {
        guard featureEnabled else { return .displayAndFocus(guideToSettings: false) }
        if permissionGranted { return .inject }
        return .displayAndFocus(guideToSettings: !onboardingAlreadyPrompted)
    }
}
