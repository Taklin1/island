import Foundation
import Testing
import IslandRelay

/// Relais settings (issue #157, PRD US14-15): the Totem address as typed in
/// the menu normalizes to the one `POST /snapshot` endpoint, and the three
/// preferences persist in UserDefaults — off by default.
@MainActor
struct RelaySettingsTests {
    @Test(
        "An address typed as IP, host:port, http:// URL or .local name normalizes to http://host[:port]/snapshot",
        arguments: [
            ("192.168.1.42", "http://192.168.1.42/snapshot"),
            ("192.168.1.42:8080", "http://192.168.1.42:8080/snapshot"),
            ("http://192.168.1.42", "http://192.168.1.42/snapshot"),
            ("http://192.168.1.42:8080/", "http://192.168.1.42:8080/snapshot"),
            ("HTTP://192.168.1.42/snapshot", "http://192.168.1.42/snapshot"),
            ("island-totem.local", "http://island-totem.local/snapshot"),
            ("  island-totem.local:80 \n", "http://island-totem.local:80/snapshot"),
        ]
    )
    func addressNormalizes(typed: String, expected: String) {
        #expect(RelaySettings.endpoint(forAddress: typed)?.absoluteString == expected)
    }

    @Test(
        "An empty, blank or unusable address is refused",
        arguments: ["", "   ", "https://192.168.1.42", "192.168.1.42:notaport", "http://", "two words.local"]
    )
    func unusableAddressIsRefused(typed: String) {
        #expect(RelaySettings.endpoint(forAddress: typed) == nil)
    }

    @Test("The Relais is off by default and has no target")
    func offByDefault() {
        let settings = RelaySettings(defaults: Self.scratchDefaults())
        #expect(settings.isEnabled == false)
        #expect(settings.target == nil)
    }

    @Test("Enabled flag, address and token persist across instances on the same defaults")
    func settingsPersist() {
        let defaults = Self.scratchDefaults()
        let first = RelaySettings(defaults: defaults)
        first.isEnabled = true
        first.address = "island-totem.local"
        first.token = "s3cret"

        let second = RelaySettings(defaults: defaults)
        #expect(second.isEnabled == true)
        #expect(second.address == "island-totem.local")
        #expect(second.token == "s3cret")
        #expect(second.target == RelayTarget(
            endpoint: URL(string: "http://island-totem.local/snapshot")!, token: "s3cret"))
    }

    @Test("Without a token or with an unusable address there is no target")
    func incompleteConfigurationHasNoTarget() {
        let settings = RelaySettings(defaults: Self.scratchDefaults())
        settings.address = "192.168.1.42"
        #expect(settings.target == nil)
        settings.token = "   "
        #expect(settings.target == nil)
        settings.token = "s3cret"
        settings.address = ""
        #expect(settings.target == nil)
    }

    static func scratchDefaults() -> UserDefaults {
        let suite = "island-relay-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
