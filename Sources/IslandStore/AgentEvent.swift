import Foundation

/// What the Island shows of a finished turn (ADR-0002): facts extracted
/// locally by an adapter from its own artifacts (e.g. the Claude Code
/// transcript), never produced by an LLM call. Every field is optional —
/// extraction is best-effort and the event must flow even when it fails.
public struct TurnSummary: Equatable, Sendable {
    /// Last assistant message of the main turn, verbatim.
    public let text: String?
    /// Completed todos at the end of the turn, when the agent kept a list.
    public let todosDone: Int?
    /// Total todos at the end of the turn, when the agent kept a list.
    public let todosTotal: Int?
    /// Files the agent modified during the turn (absolute paths, in order).
    public let filesModified: [String]
    /// Wall-clock duration of the turn, when both ends could be timestamped.
    public let turnDuration: TimeInterval?

    public init(
        text: String? = nil,
        todosDone: Int? = nil,
        todosTotal: Int? = nil,
        filesModified: [String] = [],
        turnDuration: TimeInterval? = nil
    ) {
        self.text = text
        self.todosDone = todosDone
        self.todosTotal = todosTotal
        self.filesModified = filesModified
        self.turnDuration = turnDuration
    }
}

/// Generic event schema (ADR-0004).
///
/// The store and the UI only ever see this vocabulary; anything specific to a
/// given agent tool (hook formats, transcripts…) lives in its adapter.
public struct AgentEvent: Equatable, Sendable {
    /// Stable identifier of the Session this event belongs to.
    public let sessionID: String
    /// What happened to the Session.
    public let kind: AgentEventKind
    /// Working directory of the Session (used to derive the project name).
    public let cwd: String?
    /// Terminal hosting the Session, when known.
    public let terminal: String?
    /// Which agent tool produced the event (e.g. "claude-code").
    public let agent: String
    /// What the turn produced, extracted locally by the adapter (ADR-0002).
    /// Only meaningful on `.turnEnded`; `nil` when extraction failed — the
    /// event still flows (fallback: state + project).
    public let summary: TurnSummary?
    /// Human-readable session title, extracted locally by the adapter (issue
    /// #32, e.g. from the Claude Code `ai-title` record). `nil` when the
    /// adapter could not read one on this event — the store then keeps the last
    /// known title, and the UI falls back to the project folder name.
    public let title: String?
    /// The question the tool call starting with this event will pose, parsed
    /// by the adapter from the tool's own payload (issue #77, e.g. the
    /// `tool_input` of a Claude Code `PreToolUse(AskUserQuestion)`). Only
    /// meaningful on `.toolStarted` — the store stashes it and promotes it
    /// into `Session.pendingQuestion` when the Session enters waiting. `nil`
    /// for every other tool, for an unextractable/multi-select question, and
    /// on `.waitingForUser` (a blocking notification carries no options) —
    /// the card then shows no buttons and degrades to Click-to-focus (US10).
    public let question: PendingQuestion?

    public init(
        sessionID: String,
        kind: AgentEventKind,
        cwd: String? = nil,
        terminal: String? = nil,
        agent: String,
        summary: TurnSummary? = nil,
        title: String? = nil,
        question: PendingQuestion? = nil
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.cwd = cwd
        self.terminal = terminal
        self.agent = agent
        self.summary = summary
        self.title = title
        self.question = question
    }
}

/// Session lifecycle facts, agent-agnostic. Adapters translate their native
/// events (hooks…) into these; the store turns them into Session state.
public enum AgentEventKind: Equatable, Sendable {
    /// The Session appeared (or resumed — the store upserts, never duplicates).
    case sessionStarted
    /// The user submitted a prompt: the Session starts working on a turn.
    case promptSubmitted(prompt: String)
    /// The agent is about to run a tool.
    case toolStarted(tool: String)
    /// The tool finished; the agent keeps working on the turn.
    case toolFinished(tool: String)
    /// The agent finished its turn (the Session stays alive, idle).
    ///
    /// `awaitsReply` is the adapter's local reading of whether the last
    /// assistant message ended on a question (`?`, issue #39 / ADR-0006):
    /// a question resolves to `.waiting` (orange) **immediately**, even with a
    /// subagent still live (Q5, question wins). The adapter only *detects*; it
    /// never emits `.waitingForUser` directly, which would bypass the gate.
    ///
    /// `liveSubagentCount` is the number of **Sous-agents still running at this
    /// Stop**, read from the hook's `background_tasks` list (issue #48,
    /// ADR-0008 amended): entries with `type == "subagent"` and a non-empty
    /// `id`. On a constat (`awaitsReply == false`), a non-zero count keeps the
    /// Session `.running` (the gate) — it becomes `.ended` only once a later
    /// Stop reports zero. This is race-free: the count comes from the Stop
    /// payload itself, so it never depends on a subagent's own hooks landing
    /// first, and no clock tick is needed (every subagent completion triggers a
    /// fresh main turn ⇒ a fresh Stop that re-evaluates the list).
    case turnEnded(awaitsReply: Bool, liveSubagentCount: Int)
    /// The agent is blocked on the user (permission request or question).
    case waitingForUser(message: String?)
    /// The Session closed for good: it disappears from the Island.
    case sessionEnded
}

/// Lifecycle state of a live Session. Closed Sessions are not a state: they
/// are removed from the store altogether.
public enum SessionState: Equatable, Sendable {
    /// Alive but not working (just started, or resumed).
    case idle
    /// Working on a turn (prompt submitted, tools running).
    case running
    /// Turn finished (the "agent done" state the Peek announces).
    case ended
    /// Blocked on the user: permission request or question ("attend").
    case waiting
}

extension SessionState {
    /// Priorité d'état (issue #44): the single source of how "pressing" each
    /// state is — waiting > terminé > working > idle — a lower rank being more
    /// pressing. This is the one place the order lives; the Extended card sort,
    /// the Icône animée (menu-bar mascot) and the Peek selection all read it
    /// instead of re-encoding the order inline.
    public var priorityRank: Int {
        switch self {
        case .waiting: 0
        case .ended: 1
        case .running: 2
        case .idle: 3
        }
    }
}
