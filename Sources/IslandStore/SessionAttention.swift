/// The attention the Sessions collectively ask for (issue #156): the single
/// aggregate "most pressing unacknowledged state" read by every surface that
/// reflects all Sessions at once — the Icône animée (menu-bar mascot), the
/// Liseré and the Totem Instantané. Lives here so none of them re-encodes it.
public enum SessionAttention {
    /// The most pressing state over `sessions` by the Priorité d'état
    /// (``SessionState/priorityRank``, never re-encoded here). Only
    /// *unacknowledged* waiting/ended Sessions still press: once Acknowledged
    /// (ADR-0007) they keep their state but stop weighing on the aggregate.
    /// Running/idle always count, whatever their flag. No Session, or
    /// everything acknowledged, is `.idle`.
    public static func mostPressingState(among sessions: [Session]) -> SessionState {
        sessions
            .filter(\.pressesAttention)
            .map(\.state)
            .min { $0.priorityRank < $1.priorityRank } ?? .idle
    }
}

extension Session {
    /// Whether this Session weighs on the aggregate: waiting/ended only while
    /// not yet Acknowledged, running/idle always.
    var pressesAttention: Bool {
        switch state {
        case .waiting, .ended: needsAcknowledgement
        case .running, .idle: true
        }
    }
}
