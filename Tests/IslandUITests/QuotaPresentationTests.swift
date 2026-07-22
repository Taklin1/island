import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Presentation of the Quotas section (issue #9): the SwiftUI rendering is
/// checked visually, but labels, gauge fractions and the per-card context
/// percentage are plain functions and are tested here.
@MainActor
struct QuotaPresentationTests {
    @Test("A Session card carries its context percentage when the tee reported one")
    func sessionCardCarriesContextPercentage() {
        let session = Session(id: "abc123", state: .running, agent: "claude-code")

        let with = SessionCard(session: session, contextUsedPercentage: 17.3, home: "/Users/loic")
        let without = SessionCard(session: session, home: "/Users/loic")

        #expect(with.contextLabel == "contexte 17 %")
        #expect(without.contextLabel == nil)
    }

    @Test("The global gauges carry French window labels, percents, fractions and a local reset time")
    func gaugesCarryLabelsAndFractions() throws {
        let quotas = Quotas(
            fiveHour: RateLimitWindow(
                usedPercentage: 23.5,
                resetsAt: Date(timeIntervalSince1970: 1_738_425_600)
            ),
            sevenDay: RateLimitWindow(usedPercentage: 41.2)
        )

        let gauges = QuotaGauge.gauges(for: quotas)

        #expect(gauges.count == 2)
        let fiveHour = try #require(gauges.first)
        #expect(fiveHour.windowLabel == "5 h")
        #expect(fiveHour.percentLabel == "24 %")
        #expect(fiveHour.fraction == 0.235)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let reset = try #require(fiveHour.resetLabel)
        let expected = calendar.dateComponents(
            [.hour, .minute], from: Date(timeIntervalSince1970: 1_738_425_600))
        #expect(reset == String(format: "↺ %02d:%02d", expected.hour!, expected.minute!))

        let sevenDay = try #require(gauges.last)
        #expect(sevenDay.windowLabel == "7 j")
        #expect(sevenDay.percentLabel == "41 %")
        #expect(sevenDay.resetLabel == nil)
    }

    @Test("A gauge fraction is clamped to 0…1")
    func gaugeFractionIsClamped() {
        let over = QuotaGauge.gauges(for: Quotas(
            fiveHour: RateLimitWindow(usedPercentage: 130),
            sevenDay: RateLimitWindow(usedPercentage: -5)
        ))

        #expect(over[0].fraction == 1)
        #expect(over[1].fraction == 0)
    }

    @Test("A window absent from the Quotas yields no gauge")
    func absentWindowYieldsNoGauge() {
        let onlyWeek = QuotaGauge.gauges(for: Quotas(
            sevenDay: RateLimitWindow(usedPercentage: 41.2)
        ))

        #expect(onlyWeek.count == 1)
        #expect(onlyWeek[0].windowLabel == "7 j")
    }

    @Test("The stdout quotas trace carries both windows and the reset epoch")
    func quotasTraceCarriesWindows() {
        let quotas = Quotas(
            fiveHour: RateLimitWindow(
                usedPercentage: 23.5,
                resetsAt: Date(timeIntervalSince1970: 1_738_425_600)
            ),
            sevenDay: RateLimitWindow(usedPercentage: 41.2)
        )

        #expect(IslandController.quotasTrace(for: quotas)
            == "5h=23.5% reset=1738425600 7d=41.2%")
        #expect(IslandController.quotasTrace(for: Quotas()) == "none")
    }
}
