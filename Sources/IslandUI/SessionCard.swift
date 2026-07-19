import Foundation
import IslandStore

/// Presentation model of one Session card in the Extended Island.
/// Pure data + formatting: the SwiftUI layer only lays it out.
struct SessionCard: Identifiable, Equatable {
    let id: String
    /// Project name (last component of the cwd).
    let project: String
    /// Abbreviated cwd ("~/Documents/island"), or nil when unknown.
    let location: String?
    /// French state label shown on the card.
    let stateLabel: String
    /// Compact-mode glyph for the same state.
    let glyph: String
    let lastPrompt: String?
    let currentTool: String?
    /// Start of the current turn, when the Session is working (drives the
    /// live elapsed-time display).
    let turnStartedAt: Date?
    /// Context window usage of this Session (0–100), when the statusline tee
    /// reported one (issue #9). nil = not shown.
    let contextUsedPercentage: Double?

    /// French context label of the card's Quotas section, or nil when the
    /// tee never reported a context usage for this Session.
    var contextLabel: String? {
        contextUsedPercentage.map { "contexte \(Int($0.rounded())) %" }
    }

    init(session: Session, contextUsedPercentage: Double? = nil, home: String = NSHomeDirectory()) {
        id = session.id
        project = session.projectName
        if let cwd = session.cwd, !cwd.isEmpty {
            location = cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
        } else {
            location = nil
        }
        (stateLabel, glyph) = Self.presentation(of: session.state)
        self.contextUsedPercentage = contextUsedPercentage
        lastPrompt = session.lastPrompt
        currentTool = session.currentTool
        turnStartedAt = session.turnStartedAt
    }

    static func presentation(of state: SessionState) -> (label: String, glyph: String) {
        switch state {
        case .idle: ("démarrée", "○")
        case .running: ("en cours", "●")
        case .ended: ("terminée", "✓")
        }
    }

    /// Compact "m:ss" / "h:mm:ss" rendering of an elapsed turn duration.
    static func durationText(seconds: Int) -> String {
        let (hours, minutes, secs) = (seconds / 3600, (seconds / 60) % 60, seconds % 60)
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
