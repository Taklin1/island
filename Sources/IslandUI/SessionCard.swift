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
    /// Pixel-art glyph animation of the state (issue #11): the bot screen's
    /// glyph alone, 2×, shown in front of the project name.
    let animation: SpriteAnimation
    let lastPrompt: String?
    let currentTool: String?
    /// Start of the current turn, when the Session is working (drives the
    /// live elapsed-time display).
    let turnStartedAt: Date?
    /// Context window usage of this Session (0–100), when the statusline tee
    /// reported one (issue #9). nil = not shown.
    let contextUsedPercentage: Double?
    /// Last assistant message of the finished turn (ADR-0002), shown in the
    /// card's content section. `nil` when extraction failed (fallback:
    /// state + project only).
    let summaryText: String?
    /// One compact line of turn facts — "todos 1/3 · 2 fichiers · 3:20" —
    /// keeping only what the extraction actually found.
    let summaryFacts: String?
    /// The AskUserQuestion the Session is blocked on (issue #26): its label and
    /// ordered options become the question text + one button per option. Only
    /// set while the Session is `.waiting` on an extractable question; `nil`
    /// otherwise — no buttons, the click degrades to Click-to-focus (US10).
    let question: PendingQuestion?

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
        stateLabel = Self.label(of: session.state)
        animation = SpriteAnimation.animation(for: session.state)
        self.contextUsedPercentage = contextUsedPercentage
        lastPrompt = session.lastPrompt
        currentTool = session.currentTool
        turnStartedAt = session.turnStartedAt
        summaryText = session.lastSummary?.text
        summaryFacts = session.lastSummary.flatMap(Self.factsLine(for:))
        // Buttons only ever show while waiting on a question; a stale one on a
        // resumed Session never leaks to the card.
        question = session.state == .waiting ? session.pendingQuestion : nil
    }

    /// Builds the facts line from a turn summary; every part is optional and
    /// an empty summary yields no line at all.
    private static func factsLine(for summary: TurnSummary) -> String? {
        var parts: [String] = []
        if let done = summary.todosDone, let total = summary.todosTotal {
            parts.append("todos \(done)/\(total)")
        }
        switch summary.filesModified.count {
        case 0: break
        case 1: parts.append("1 fichier")
        case let n: parts.append("\(n) fichiers")
        }
        if let duration = summary.turnDuration {
            parts.append(durationText(seconds: max(0, Int(duration))))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// The one-line Peek for a finished turn: first meaningful line of the
    /// summary after the project name, or the bare "terminé" fallback when
    /// the transcript could not be summarized (ADR-0002: the notification
    /// always goes out).
    static func peekLine(project: String, summaryText: String?, maxLength: Int = 80) -> String {
        let headline = summaryText
            .flatMap(firstMeaningfulLine(of:))
            .map { truncate($0, at: maxLength) }
        return "\(project) ✓ \(headline ?? "terminé")"
    }

    /// First non-empty line, shedding markdown heading/list markers so the
    /// Peek reads as a sentence.
    private static func firstMeaningfulLine(of text: String) -> String? {
        for line in text.split(separator: "\n") {
            let stripped = line
                .trimmingCharacters(in: .whitespaces)
                .drop(while: { "#->*• ".contains($0) })
                .trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { return stripped }
        }
        return nil
    }

    /// Cuts on a word boundary and appends an ellipsis when over the limit.
    private static func truncate(_ text: String, at limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        let cut = head.lastIndex(where: { $0 == " " }).map { head[..<$0] } ?? head
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    static func label(of state: SessionState) -> String {
        switch state {
        case .idle: "démarrée"
        case .running: "en cours"
        case .ended: "terminée"
        case .waiting: "attend"
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
