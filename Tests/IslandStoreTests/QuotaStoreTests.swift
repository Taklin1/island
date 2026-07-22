import Foundation
import Testing

@testable import IslandStore

/// Quota seam (issue #9): statusline JSON payloads → published Quotas
/// (global 5 h / 7 d gauges) and per-Session context usage. Behavioral only:
/// feed payloads, assert what the store publishes.
@MainActor
struct QuotaStoreTests {
    /// Real-shaped statusline payload (see docs/en/statusline): rate_limits
    /// present after the first API call, resets_at in Unix epoch seconds.
    static let fullFixture = """
    {
      "session_id": "quota-sess-1",
      "transcript_path": "/tmp/quota-sess-1.jsonl",
      "cwd": "/Users/loic/Documents/island",
      "model": { "id": "claude-opus-4-6", "display_name": "Opus" },
      "workspace": { "current_dir": "/Users/loic/Documents/island" },
      "context_window": { "used_percentage": 8.4, "remaining_percentage": 91.6 },
      "rate_limits": {
        "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
        "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
      }
    }
    """

    @Test("A full statusline payload publishes the 5 h / 7 d gauges and the reset time")
    func fullPayloadPublishesQuotas() throws {
        let store = QuotaStore()
        let update = try #require(QuotaUpdate(statuslineJSON: Data(Self.fullFixture.utf8)))

        store.apply(update)

        let quotas = try #require(store.quotas)
        #expect(quotas.fiveHour?.usedPercentage == 23.5)
        #expect(quotas.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_738_425_600))
        #expect(quotas.sevenDay?.usedPercentage == 41.2)
    }

    /// Before any API call, the statusline payload has no `rate_limits` at
    /// all: the gauges must stay hidden — never a misleading 0 %.
    @Test("A payload without rate_limits keeps the gauges hidden but tracks the context")
    func payloadWithoutRateLimitsHidesGauges() throws {
        let fixture = """
        {
          "session_id": "quota-sess-2",
          "cwd": "/tmp/projet-a",
          "model": { "id": "claude-opus-4-6", "display_name": "Opus" },
          "context_window": { "used_percentage": 12 }
        }
        """
        let store = QuotaStore()

        store.apply(try #require(QuotaUpdate(statuslineJSON: Data(fixture.utf8))))

        #expect(store.quotas == nil)
        #expect(store.contextBySession["quota-sess-2"] == 12)
    }

    @Test("Known quotas survive a later payload without rate_limits; context stays per Session")
    func quotasSurviveQuietPayloads() throws {
        let store = QuotaStore()
        store.apply(try #require(QuotaUpdate(statuslineJSON: Data(Self.fullFixture.utf8))))
        let quiet = """
        { "session_id": "quota-sess-2", "context_window": { "used_percentage": 55.5 } }
        """

        store.apply(try #require(QuotaUpdate(statuslineJSON: Data(quiet.utf8))))

        #expect(store.quotas?.fiveHour?.usedPercentage == 23.5)
        #expect(store.contextBySession["quota-sess-1"] == 8.4)
        #expect(store.contextBySession["quota-sess-2"] == 55.5)
    }

    @Test("A payload that is not a JSON object is rejected")
    func malformedPayloadIsRejected() {
        #expect(QuotaUpdate(statuslineJSON: Data("not json".utf8)) == nil)
        #expect(QuotaUpdate(statuslineJSON: Data("[1,2]".utf8)) == nil)
    }
}
