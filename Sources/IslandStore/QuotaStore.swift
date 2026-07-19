import Foundation

/// One rate-limit window (5 h or 7 d) as the statusline reports it.
public struct RateLimitWindow: Equatable, Sendable {
    /// Percentage of the window consumed, 0–100.
    public let usedPercentage: Double
    /// When the window rolls back to 0, when known.
    public let resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date? = nil) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

/// Global Claude usage Quotas (CONTEXT.md): the 5 h and 7 d windows received
/// via the statusline tee. Each window may be independently absent.
public struct Quotas: Equatable, Sendable {
    public let fiveHour: RateLimitWindow?
    public let sevenDay: RateLimitWindow?

    public init(fiveHour: RateLimitWindow? = nil, sevenDay: RateLimitWindow? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

/// What one statusline payload teaches us: the global Quotas (absent until
/// the first API call of any session — gauges stay hidden, never a misleading
/// zero) and the context usage of the Session the payload belongs to.
public struct QuotaUpdate: Equatable, Sendable {
    public let sessionID: String?
    public let contextUsedPercentage: Double?
    public let quotas: Quotas?

    /// Defensive parse of the JSON Claude Code pipes into the statusline
    /// command. Returns nil when the payload is not a JSON object — anything
    /// else degrades field by field (absent `rate_limits` is normal).
    public init?(statuslineJSON data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let payload = json as? [String: Any]
        else { return nil }

        sessionID = payload["session_id"] as? String
        let contextWindow = payload["context_window"] as? [String: Any]
        contextUsedPercentage = Self.percentage(contextWindow?["used_percentage"])

        let rateLimits = payload["rate_limits"] as? [String: Any]
        let fiveHour = Self.window(rateLimits?["five_hour"])
        let sevenDay = Self.window(rateLimits?["seven_day"])
        quotas = (fiveHour == nil && sevenDay == nil)
            ? nil
            : Quotas(fiveHour: fiveHour, sevenDay: sevenDay)
    }

    private static func window(_ value: Any?) -> RateLimitWindow? {
        guard let window = value as? [String: Any],
              let used = percentage(window["used_percentage"])
        else { return nil }
        let resetsAt = (window["resets_at"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
        return RateLimitWindow(usedPercentage: used, resetsAt: resetsAt)
    }

    /// `used_percentage` may be an int, a double, or null.
    private static func percentage(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        return number.doubleValue
    }
}

/// Publishes the Quotas gauges and the per-Session context usage from the
/// stream of statusline updates. Main-actor bound: the UI observes it
/// directly, like SessionStore.
@MainActor
public final class QuotaStore: ObservableObject {
    /// nil until a payload carries `rate_limits`: the gauges stay hidden.
    @Published public private(set) var quotas: Quotas?
    /// Context window usage (0–100) per Session ID.
    @Published public private(set) var contextBySession: [String: Double] = [:]

    public init() {}

    public func apply(_ update: QuotaUpdate) {
        if let newQuotas = update.quotas {
            quotas = newQuotas
        }
        if let sessionID = update.sessionID,
           let context = update.contextUsedPercentage {
            contextBySession[sessionID] = context
        }
    }
}
