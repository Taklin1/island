import IslandStore
import Testing
@testable import IslandUI

/// Vertical section order of the Extended panel (#69): the Quotas gauges lead so
/// they are the first thing visible when the panel opens — above the Session
/// cards, not at the foot as before. Pure like ``SessionCardsView/cappedHeight``,
/// so the order is pinned here while the rendering is verified visually.
@MainActor
struct PanelSectionOrderTests {
    @Test("Quotas lead, above the Session cards")
    func quotasLeadAboveCards() {
        let sections = SessionCardsView.sections(hasQuotas: true, hasCards: true)
        #expect(sections == [.quotas, .cards])
    }

    @Test("With no Sessions, the gauges still sit above the empty placeholder")
    func quotasLeadAboveEmptyPlaceholder() {
        let sections = SessionCardsView.sections(hasQuotas: true, hasCards: false)
        #expect(sections == [.quotas, .emptyPlaceholder])
    }

    @Test("Without reported quotas nothing leads: just the cards, or the placeholder")
    func noQuotasNoLeadingGauge() {
        #expect(SessionCardsView.sections(hasQuotas: false, hasCards: true) == [.cards])
        #expect(SessionCardsView.sections(hasQuotas: false, hasCards: false) == [.emptyPlaceholder])
    }
}
