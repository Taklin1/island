import Foundation
import Testing

import IslandStore

/// The single aggregate "most pressing unacknowledged state" (issue #156),
/// shared by the Icône animée, the Liseré and the Totem Instantané.
struct SessionAttentionTests {
    private static func session(
        _ id: String, _ state: SessionState, ack needsAcknowledgement: Bool = false
    ) -> Session {
        Session(id: id, state: state, agent: "claude-code", needsAcknowledgement: needsAcknowledgement)
    }

    struct Case: CustomTestStringConvertible, Sendable {
        let label: String
        let sessions: [Session]
        let expected: SessionState
        var testDescription: String { label }
    }

    static let cases: [Case] = [
        Case(label: "no Session is idle", sessions: [], expected: .idle),
        Case(label: "unacknowledged waiting wins over everything", sessions: [
            session("a", .running),
            session("b", .ended, ack: true),
            session("c", .waiting, ack: true),
            session("d", .idle),
        ], expected: .waiting),
        Case(label: "unacknowledged ended wins over working and idle", sessions: [
            session("a", .running),
            session("b", .idle),
            session("c", .ended, ack: true),
        ], expected: .ended),
        Case(label: "working wins over idle", sessions: [
            session("a", .idle),
            session("b", .running),
        ], expected: .running),
        Case(label: "acknowledged waiting/ended no longer press", sessions: [
            session("a", .waiting),
            session("b", .ended),
            session("c", .idle),
        ], expected: .idle),
        Case(label: "acknowledged waiting yields to a running Session", sessions: [
            session("a", .waiting),
            session("b", .running),
        ], expected: .running),
        // Stop with live background tasks keeps a Session `.running` while a
        // previous flag may still be set (SessionStore turnEnded gate): it
        // presses as working, never as done.
        Case(label: "running flagged Session presses as working", sessions: [
            session("a", .running, ack: true),
            session("b", .idle),
        ], expected: .running),
        Case(label: "idle flagged Session stays idle", sessions: [
            session("a", .idle, ack: true),
        ], expected: .idle),
    ]

    @Test("The most pressing unacknowledged state follows the Priorité d'état", arguments: cases)
    func mostPressingState(_ testCase: Case) {
        #expect(SessionAttention.mostPressingState(among: testCase.sessions) == testCase.expected)
    }
}
