import AppKit
import ApplicationServices

/// The Accessibility permission that the injection of #27 needs (issue #28).
/// macOS gates `CGEvent` posting behind this permission, granted **per binary**
/// (so it must be re-granted for `island.app` after packaging — hence the
/// onboarding). Wrapped behind a seam so the gate logic (`AnswerFromIslandGate`)
/// stays testable without touching the real TCC database; production uses
/// `.live`.
///
/// NB: `AXIsProcessTrusted()` can report a **stale** value until the app is
/// relaunched after the grant (spike #25, issue #28) — the onboarding message
/// tells the user to relaunch.
@MainActor
public struct AccessibilityPermission {
    private let isTrusted: () -> Bool

    public init(isTrusted: @escaping () -> Bool) {
        self.isTrusted = isTrusted
    }

    /// Whether the process is currently trusted for Accessibility.
    public var isGranted: Bool { isTrusted() }

    /// Production detector, backed by the real Accessibility API.
    public static let live = AccessibilityPermission(isTrusted: { AXIsProcessTrusted() })
}

/// Onboarding to the Accessibility permission (issue #28, US8): guides the user
/// toward System Settings without ever blocking — the feature keeps degrading to
/// display + focus until the grant (ADR-0009, "guider sans forcer"). Seam-wrapped
/// so the wiring stays free of side effects in tests; production uses `.live`.
@MainActor
public struct AccessibilityOnboarding {
    private let guide: () -> Void

    public init(guide: @escaping () -> Void) {
        self.guide = guide
    }

    /// Surfaces the system permission prompt and/or the Accessibility pane.
    /// Non-blocking; the caller has already decided this is the first no-permission
    /// use (`AnswerFromIslandAction.displayAndFocus(guideToSettings: true)`).
    public func guideToSystemSettings() { guide() }

    /// Production onboarding: the canonical system prompt (its button opens
    /// System Settings), then a deep link to the Accessibility pane as a fallback
    /// when the prompt is suppressed (already answered once this session).
    public static let live = AccessibilityOnboarding(guide: {
        // `kAXTrustedCheckOptionPrompt` is a C global `var` (not concurrency-safe
        // under Swift 6); its documented value is this literal string.
        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    })
}
