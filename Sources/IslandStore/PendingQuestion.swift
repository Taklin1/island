import Foundation

/// A question the agent is blocked on — an `AskUserQuestion` tool call —
/// extracted locally from the transcript (ADR-0002, spike #25), never produced
/// by an LLM call.
///
/// Present on a Session only while it is `.waiting` on an *extractable* single
/// question. A permission prompt, free text, an answered question, or a
/// multi-question turn all yield `nil`: the card then shows no buttons and the
/// click degrades to Click-to-focus (US10).
public struct PendingQuestion: Equatable, Sendable {
    /// The question label shown above the options (the `question` field).
    public let prompt: String
    /// The options in transcript order. The index (0, 1, 2…) *is* the mapping
    /// to the TUI selector key (1, 2, 3…) that the injection of #27 will send;
    /// #26 only displays it.
    public let options: [Option]

    public init(prompt: String, options: [Option]) {
        self.prompt = prompt
        self.options = options
    }

    /// One selectable answer of a ``PendingQuestion``.
    public struct Option: Equatable, Sendable {
        /// The answer label shown on the button.
        public let label: String
        /// The longer description Claude attached to the option, when present.
        public let description: String?

        public init(label: String, description: String? = nil) {
            self.label = label
            self.description = description
        }
    }
}
