import Foundation

/// Where the Relais pushes and with which shared token (ADR-0014): the one
/// `POST http://<address>/snapshot` endpoint and the `X-Island-Token` value.
public struct RelayTarget: Equatable, Sendable {
    public let endpoint: URL
    public let token: String

    public init(endpoint: URL, token: String) {
        self.endpoint = endpoint
        self.token = token
    }
}

/// The Relais preferences (issue #157, PRD US14-15), persisted in UserDefaults:
/// on/off (OFF by default — no POST ever leaves the Mac without an explicit
/// menu action), the Totem address as typed, and the Totem token. The token
/// is deliberately NOT `TokenStore` / `~/.claude/island-token`, which
/// authenticates the hooks' inbound path: the Totem gets its own secret.
public struct RelaySettings {
    public static let enabledKey = "totemRelayEnabled"
    public static let addressKey = "totemRelayAddress"
    public static let tokenKey = "totemRelayToken"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.enabledKey: false])
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// The address as the user typed it (normalized only when read as
    /// ``target``), nil until set.
    public var address: String? {
        get { defaults.string(forKey: Self.addressKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.addressKey) }
    }

    public var token: String? {
        get { defaults.string(forKey: Self.tokenKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.tokenKey) }
    }

    /// The push target, or nil while the address is unusable or the token is
    /// blank (the Totem refuses any Instantané without its token, so pushing
    /// without one would only ever be refused).
    public var target: RelayTarget? {
        guard let endpoint = address.flatMap(Self.endpoint(forAddress:)),
            let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else { return nil }
        return RelayTarget(endpoint: endpoint, token: token)
    }

    /// Pure: normalizes what the user typed — `192.168.1.42`, `host:8080`,
    /// `http://host[:port][/…]`, `island-totem.local` (the name the firmware
    /// announces over mDNS) — to `http://host[:port]/snapshot`. Any typed path
    /// is dropped: the route is fixed by the contract. Nil for a blank
    /// address, another scheme (no TLS, ADR-0014) or an unparseable host/port.
    public static func endpoint(forAddress typed: String) -> URL? {
        var rest = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.lowercased().hasPrefix("http://") {
            rest.removeFirst("http://".count)
        } else if rest.contains("://") {
            return nil
        }
        let hostPort = rest.prefix { $0 != "/" }
        guard !hostPort.isEmpty,
            let parsed = URLComponents(string: "http://\(hostPort)"),
            let host = parsed.host, !host.isEmpty,
            parsed.user == nil, parsed.password == nil
        else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = parsed.port
        components.path = "/snapshot"
        return components.url
    }
}
