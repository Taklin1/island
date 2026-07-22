import Testing
import IslandStore

struct AnswerFromIslandGateTests {
    @Test("Feature off degrades to display + focus — never injects, even with permission")
    func featureOffNeverInjects() {
        let action = AnswerFromIslandGate.action(
            featureEnabled: false,
            permissionGranted: true,
            onboardingAlreadyPrompted: false
        )

        #expect(action == .displayAndFocus(guideToSettings: false))
    }

    @Test("Feature on with permission granted injects")
    func featureOnWithPermissionInjects() {
        let action = AnswerFromIslandGate.action(
            featureEnabled: true,
            permissionGranted: true,
            onboardingAlreadyPrompted: false
        )

        #expect(action == .inject)
    }

    @Test("Feature on without permission, first use, guides to System Settings then degrades")
    func featureOnWithoutPermissionFirstUseGuides() {
        let action = AnswerFromIslandGate.action(
            featureEnabled: true,
            permissionGranted: false,
            onboardingAlreadyPrompted: false
        )

        #expect(action == .displayAndFocus(guideToSettings: true))
    }

    @Test("Feature on without permission, already prompted, degrades without nagging")
    func featureOnWithoutPermissionAlreadyPromptedDoesNotNag() {
        let action = AnswerFromIslandGate.action(
            featureEnabled: true,
            permissionGranted: false,
            onboardingAlreadyPrompted: true
        )

        #expect(action == .displayAndFocus(guideToSettings: false))
    }

    @Test("Feature off never guides — the user opted out")
    func featureOffNeverGuides() {
        let action = AnswerFromIslandGate.action(
            featureEnabled: false,
            permissionGranted: false,
            onboardingAlreadyPrompted: false
        )

        #expect(action == .displayAndFocus(guideToSettings: false))
    }
}

/// The shared Accessibility-onboarding latch (issues #28 → #36): ONE guidance
/// to System Settings for the whole app — card click or option tap, whichever
/// comes first without the permission — and never again after.
struct AccessibilityGuidanceTests {
    @Test("First use without the permission guides; the latch silences every later trigger")
    func guidesOnceThenNever() {
        #expect(AccessibilityGuidance.shouldGuide(
            permissionGranted: false, alreadyPrompted: false))
        #expect(!AccessibilityGuidance.shouldGuide(
            permissionGranted: false, alreadyPrompted: true))
    }

    @Test("With the permission granted there is nothing to guide to")
    func permissionGrantedNeverGuides() {
        #expect(!AccessibilityGuidance.shouldGuide(
            permissionGranted: true, alreadyPrompted: false))
        #expect(!AccessibilityGuidance.shouldGuide(
            permissionGranted: true, alreadyPrompted: true))
    }
}
