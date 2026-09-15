import Foundation

/// The Instantané pushed to the Totem (issue #156, ADR-0013): the aggregated
/// state of the Sessions by the Priorité d'état, the raw per-state counts and
/// the Quotas. Only states and percentages — never an Événement, a Session
/// text or a Session identifier ever leaves the Mac.
///
/// The value itself is dateless so two Instantanés compare equal when their
/// content does (the Relais only pushes on change); the emission timestamp is
/// stamped at encoding time by ``encode(sentAt:)``.
public struct TotemSnapshot: Equatable, Sendable {
    /// The contract's aggregated state, mapped explicitly from
    /// ``SessionState`` — deliberately not the ADR-0012 UI labels.
    public enum State: String, Equatable, Sendable, Encodable {
        case idle
        case working
        case done
        case waiting

        init(_ state: SessionState) {
            switch state {
            case .idle: self = .idle
            case .running: self = .working
            case .ended: self = .done
            case .waiting: self = .waiting
            }
        }
    }

    /// How many Sessions are in each *raw* state: an acknowledged waiting
    /// Session still counts as waiting. The sum is the number of Sessions.
    public struct Counts: Equatable, Sendable, Encodable {
        public let waiting: Int
        public let done: Int
        public let working: Int
        public let idle: Int

        public init(waiting: Int, done: Int, working: Int, idle: Int) {
            self.waiting = waiting
            self.done = done
            self.working = working
            self.idle = idle
        }
    }

    /// One Quotas window as the Totem sees it: whole percent (same rounding
    /// as the Mac gauges) and, when known, the reset as whole Unix epoch
    /// seconds — no time zone: the Totem shows a relative countdown only.
    public struct Window: Equatable, Sendable, Encodable {
        public let usedPercentage: Int
        public let resetsAt: Int?

        public init(usedPercentage: Int, resetsAt: Int? = nil) {
            self.usedPercentage = usedPercentage
            self.resetsAt = resetsAt
        }

        init(_ window: RateLimitWindow) {
            self.init(
                usedPercentage: window.roundedUsedPercentage,
                resetsAt: window.resetsAt.flatMap(unixEpochSeconds)
            )
        }
    }

    /// The 5 h and 7 d windows; each independently absent (key omitted).
    public struct QuotaWindows: Equatable, Sendable, Encodable {
        public let fiveHour: Window?
        public let sevenDay: Window?

        public init(fiveHour: Window? = nil, sevenDay: Window? = nil) {
            self.fiveHour = fiveHour
            self.sevenDay = sevenDay
        }
    }

    /// Version of the JSON contract (`v`), pinned by `firmware/contract/`.
    public static let contractVersion = 1

    public let state: State
    public let counts: Counts
    /// `nil` until the statusline reported rate limits (key omitted).
    public let quotas: QuotaWindows?
    /// `true` only on the closing Instantané (``empty``).
    public let shutdown: Bool

    public init(state: State, counts: Counts, quotas: QuotaWindows?, shutdown: Bool) {
        self.state = state
        self.counts = counts
        self.quotas = quotas
        self.shutdown = shutdown
    }

    /// The closing Instantané, sent when the app shuts down: idle, zero
    /// counts, no Quotas, `shutdown: true`.
    public static let empty = TotemSnapshot(
        state: .idle,
        counts: Counts(waiting: 0, done: 0, working: 0, idle: 0),
        quotas: nil,
        shutdown: true
    )

    /// The Instantané of the live Sessions and Quotas. Pure: no clock, no
    /// actor — the aggregate is ``SessionAttention/mostPressingState(among:)``,
    /// the counts are each Session's raw state. Reads nothing but states and
    /// percentages, so no Session text or identifier can leak.
    public static func make(sessions: [Session], quotas: Quotas?) -> TotemSnapshot {
        let states = sessions.map { State($0.state) }
        let fiveHour = quotas?.fiveHour.map(Window.init)
        let sevenDay = quotas?.sevenDay.map(Window.init)
        return TotemSnapshot(
            state: State(SessionAttention.mostPressingState(among: sessions)),
            counts: Counts(
                waiting: states.count(where: { $0 == .waiting }),
                done: states.count(where: { $0 == .done }),
                working: states.count(where: { $0 == .working }),
                idle: states.count(where: { $0 == .idle })
            ),
            quotas: (fiveHour == nil && sevenDay == nil)
                ? nil
                : QuotaWindows(fiveHour: fiveHour, sevenDay: sevenDay),
            shutdown: false
        )
    }

    /// The contract JSON: compact, keys sorted (stable byte for byte, see
    /// `firmware/contract/`), absent optionals omitted (never `null`), dates
    /// as whole Unix epoch seconds. `sentAt` is injected so the encoding is
    /// deterministic under test.
    public func encode(sentAt: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(
            v: Self.contractVersion,
            state: state,
            counts: counts,
            quotas: quotas,
            // The emission clock is the real one: always representable.
            sentAt: unixEpochSeconds(sentAt) ?? 0,
            shutdown: shutdown
        ))
    }

    /// The wire shape: the comparable content plus the emission stamp.
    private struct Envelope: Encodable {
        let v: Int
        let state: State
        let counts: Counts
        let quotas: QuotaWindows?
        let sentAt: Int
        let shutdown: Bool
    }
}

/// Whole seconds since 1970 (floored) — never a raw `Date`, whose default
/// `JSONEncoder` strategy counts from 2001. `nil` when the instant does not
/// fit an `Int` (an absurd statusline `resets_at` must not trap the app).
private func unixEpochSeconds(_ date: Date) -> Int? {
    Int(exactly: date.timeIntervalSince1970.rounded(.down))
}
