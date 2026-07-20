import Testing
import IslandStore

struct AppVersionTests {
    @Test("A bare release version is exposed as-is and is not a dev build")
    func releaseVersionIsNotDev() {
        let version = AppVersion(bundleShortVersion: "0.1.24")

        #expect(version.value == "0.1.24")
        #expect(version.isDev == false)
    }

    @Test("A -dev suffixed version is exposed as-is and detected as a dev build")
    func devSuffixedVersionIsDev() {
        let version = AppVersion(bundleShortVersion: "0.1.24-dev")

        #expect(version.value == "0.1.24-dev")
        #expect(version.isDev == true)
    }

    @Test("No bundle version (bare SwiftPM binary) falls back to a readable dev value")
    func missingBundleVersionFallsBackToReadableDevValue() {
        let version = AppVersion(bundleShortVersion: nil)

        #expect(version.value == "0.0.0-dev")
        #expect(version.isDev == true)
    }

    @Test("An empty bundle version is never shown — same readable dev fallback")
    func emptyBundleVersionFallsBackToReadableDevValue() {
        let version = AppVersion(bundleShortVersion: "")

        #expect(version.value == "0.0.0-dev")
        #expect(version.isDev == true)
    }
}
