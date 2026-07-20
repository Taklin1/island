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
