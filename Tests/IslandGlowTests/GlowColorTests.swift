import Foundation
import Testing
import IslandGlow
import IslandStore

@MainActor
struct GlowColorTests {
    private func session(
        _ id: String, state: SessionState, needsAcknowledgement: Bool
    ) -> Session {
        Session(
            id: id, state: state, agent: "claude-code",
            needsAcknowledgement: needsAcknowledgement
        )
    }

    @Test("No pending Acknowledgement, no Liseré")
    func noPendingSessionMeansNoGlow() {
        let sessions = [
            session("s1", state: .running, needsAcknowledgement: false),
            session("s2", state: .idle, needsAcknowledgement: false),
        ]

        #expect(GlowColor.desired(for: sessions, enabled: true) == nil)
    }

    @Test("A waiting Session pending Acknowledgement lights the Liseré orange")
    func waitingSessionLightsOrange() {
        let sessions = [session("s1", state: .waiting, needsAcknowledgement: true)]

        #expect(GlowColor.desired(for: sessions, enabled: true) == .orange)
    }

    @Test("A finished Session pending Acknowledgement lights the Liseré green")
    func endedSessionLightsGreen() {
        let sessions = [session("s1", state: .ended, needsAcknowledgement: true)]

        #expect(GlowColor.desired(for: sessions, enabled: true) == .green)
    }

    @Test("Orange wins over green when both states coexist")
    func orangeWinsOverGreen() {
        let sessions = [
            session("done", state: .ended, needsAcknowledgement: true),
            session("blocked", state: .waiting, needsAcknowledgement: true),
        ]

        #expect(GlowColor.desired(for: sessions, enabled: true) == .orange)
    }

    @Test("An acknowledged Session never lights the Liseré")
    func acknowledgedSessionsAreDark() {
        let sessions = [
            session("done", state: .ended, needsAcknowledgement: false),
            session("blocked", state: .waiting, needsAcknowledgement: false),
        ]

        #expect(GlowColor.desired(for: sessions, enabled: true) == nil)
    }

    @Test("Liseré preference off: never lit, whatever the Sessions")
    func disabledPreferenceWinsOverEverything() {
        let sessions = [
            session("blocked", state: .waiting, needsAcknowledgement: true)
        ]

        #expect(GlowColor.desired(for: sessions, enabled: false) == nil)
    }
}
