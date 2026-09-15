import IslandStore

/// Color of the Liseré (issue #8): the luminous outline drawn on the screen
/// edges while a marking event awaits Acknowledgement.
public enum GlowColor: Equatable, Sendable {
    /// A Session waits on the user (permission or question).
    case orange
    /// A Session finished its turn.
    case green

    /// The color the Liseré should show for the given Sessions — or `nil`
    /// (no Liseré) when nothing awaits Acknowledgement or the preference is
    /// off. Orange always wins over green: a blocked agent matters more than
    /// a finished one.
    public static func desired(for sessions: [Session], enabled: Bool) -> GlowColor? {
        guard enabled else { return nil }
        // Same aggregate as the Icône animée and the Totem (issue #156):
        // only unacknowledged waiting/ended press, waiting ranks first.
        switch SessionAttention.mostPressingState(among: sessions) {
        case .waiting: return .orange
        case .ended: return .green
        case .running, .idle: return nil
        }
    }
}
