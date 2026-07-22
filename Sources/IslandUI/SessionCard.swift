import Foundation
import IslandStore

/// Presentation model of one Session card in the Extended Island.
/// Pure data + formatting: the SwiftUI layer only lays it out.
struct SessionCard: Identifiable, Equatable {
    let id: String
    /// Header line of the card (issue #32): the session title (Claude Code's
    /// `ai-title`, reflecting `/rename`), falling back to the project folder
    /// name when no title is known yet. Shown on top; the path goes underneath.
    let title: String
    /// Project name (last component of the cwd).
    let project: String
    /// Abbreviated cwd ("~/Documents/island"), or nil when unknown.
    let location: String?
    /// State label shown on the card.
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
    /// One compact line of turn facts — "todos 1/3 · 2 files · 3:20" —
    /// keeping only what the extraction actually found.
    let summaryFacts: String?
    /// Background tasks (Sous-agents, workflows…) still running under this
    /// Session (issue #48, widened by #79, Q6). Drives the discreet tally on
    /// the card; zero when none run.
    let activeBackgroundTaskCount: Int
    /// The AskUserQuestion the Session is blocked on (issue #26): its label and
    /// ordered options become the question text + one button per option. Only
    /// set while the Session is `.waiting` on an extractable question; `nil`
    /// otherwise — no buttons, the click degrades to Click-to-focus (US10).
    let question: PendingQuestion?
    /// The human-readable ask of a *buttonless* wait (issue #29): shown when the
    /// Session waits with no extractable options — an escalated permission
    /// prompt ("Claude needs your permission to use Bash") or an unextractable
    /// question (US10) — so the card still says WHAT is blocking. Display only;
    /// the click degrades to Click-to-focus, nothing is ever injected (US7).
    /// `nil` whenever there are buttons, the Session is not waiting, or no
    /// message rode the block.
    let waitingMessage: String?

    /// Context label of the card's Quotas section, or nil when the tee never
    /// reported a context usage for this Session.
    var contextLabel: String? {
        contextUsedPercentage.map { "context \(Int($0.rounded()))%" }
    }

    /// Discreet tally of live background tasks (issue #48, widened by #79, Q6),
    /// or nil when none run — "1 background task running" /
    /// "3 background tasks running". Type-neutral wording on purpose: the count
    /// mixes Sous-agents, workflows, shell tasks… and no per-type treatment is
    /// wanted (out of #79's scope).
    var backgroundTasksLabel: String? {
        guard activeBackgroundTaskCount > 0 else { return nil }
        let noun = activeBackgroundTaskCount == 1 ? "background task" : "background tasks"
        return "\(activeBackgroundTaskCount) \(noun) running"
    }

    init(session: Session, contextUsedPercentage: Double? = nil, home: String = NSHomeDirectory()) {
        id = session.id
        project = session.projectName
        title = session.title ?? session.projectName
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
        activeBackgroundTaskCount = session.activeBackgroundTaskCount
        // Buttons only ever show while waiting on a question; a stale one on a
        // resumed Session never leaks to the card.
        question = session.state == .waiting ? session.pendingQuestion : nil
        // The ask of a buttonless wait (#29): only while waiting AND with no
        // question — buttons carry their own label, and a stale message on a
        // resumed Session never leaks.
        waitingMessage = (session.state == .waiting && session.pendingQuestion == nil)
            ? session.waitingMessage : nil
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
        case 1: parts.append("1 file")
        case let n: parts.append("\(n) files")
        }
        if let duration = summary.turnDuration {
            parts.append(durationText(seconds: max(0, Int(duration))))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// The one-line Peek for a finished turn: first meaningful line of the
    /// summary after the project name, or the bare "done" fallback when
    /// the transcript could not be summarized (ADR-0002: the notification
    /// always goes out).
    static func peekLine(project: String, summaryText: String?, maxLength: Int = 80) -> String {
        let headline = summaryText
            .flatMap(firstMeaningfulLine(of:))
            .map { truncate($0, at: maxLength) }
        return "\(project) ✓ \(headline ?? "done")"
    }

    /// The one-line Peek for a Session waiting on the user. When the wait comes
    /// from a turn that ended on a question (#39, ADR-0006), show the question
    /// itself — « projet · waiting: "…?" » — so the answer is one glance away;
    /// otherwise (a permission/AskUserQuestion wait, which carries no summary)
    /// keep the historical call to action « projet ? waiting for a reply ».
    static func waitingPeekLine(project: String, questionText: String?, maxLength: Int = 80) -> String {
        guard let question = questionText.flatMap(lastQuestionLine(of:)) else {
            return "\(project) ? waiting for a reply"
        }
        return "\(project) · waiting: \"\(truncate(question, at: maxLength))\""
    }

    /// The final question line of an assistant message, when the message ends
    /// on one (#39): the message is right-trimmed and kept only if it ends with
    /// `?` (same rule the adapter used to classify the turn), then its last
    /// non-empty line is returned so the Peek shows the question, not the lead-in.
    private static func lastQuestionLine(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("?") else { return nil }
        for line in trimmed.split(separator: "\n").reversed() {
            let stripped = line
                .trimmingCharacters(in: .whitespaces)
                .drop(while: { "#->*• ".contains($0) })
                .trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { return stripped }
        }
        return nil
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
        case .idle: "started"
        case .running: "working"
        case .ended: "done"
        case .waiting: "waiting"
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
