import Combine
import DynamicNotchKit
import IslandStore
import SwiftUI

/// Drives the Island (ADR-0003): a compact floating bar by default — one
/// pixel-art Sprite per live Session (issue #11) — and two expansions, only
/// ever triggered by:
/// - a 2-3 s Peek when a Session finishes its turn (then back to compact);
/// - hovering the Island, which shows the Extended mode (one card per
///   Session: project, state, last prompt, running tool, elapsed time) and
///   folds back to compact as soon as the pointer leaves.
///
/// The Island never expands on its own outside those two paths. The panel is
/// non-activating (DynamicNotchKit uses a `.nonactivatingPanel`), so it never
/// steals focus from the terminal.
///
/// Depends only on the generic session store (ADR-0004). Store updates are
/// throttled before touching the view model: PreToolUse/PostToolUse arrive at
/// high rate and must not trigger one render each.
@MainActor
public final class IslandController {
    private enum Mode {
        case compact
        case peek
        case expandedHover
    }

    private let store: SessionStore
    private let quotaStore: QuotaStore
    /// Click-to-focus (issue #10): brings the Session's terminal frontmost.
    /// Injected so the UI never depends on a concrete terminal module.
    private let focusTerminal: ((String?) -> Void)?
    private let viewModel = IslandViewModel()
    private var notch: DynamicNotch<ExpandedContentView, CompactLeadingView, CompactTrailingView>?
    private var cancellables: Set<AnyCancellable> = []
    private var knownEndedSessionIDs: Set<String> = []
    private var knownWaitingSessionIDs: Set<String> = []
    private var peekTask: Task<Void, Never>?
    private var mode: Mode = .compact

    /// How long a Peek stays on screen before folding back to compact.
    private let peekDuration: Duration = .seconds(2.5)
    /// Store updates are coalesced to at most one UI refresh per interval.
    private let refreshInterval: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(200)

    public init(
        store: SessionStore,
        quotaStore: QuotaStore = QuotaStore(),
        focusTerminal: ((String?) -> Void)? = nil
    ) {
        self.store = store
        self.quotaStore = quotaStore
        self.focusTerminal = focusTerminal
        viewModel.activateSession = { [weak self] sessionID in
            self?.cardActivated(sessionID: sessionID)
        }
    }

    /// Shows the compact Island and starts reacting to session changes.
    public func activate() async {
        let viewModel = viewModel
        // `.notch` (not `.auto`/`.floating`): in DynamicNotchKit, the floating
        // style *hides* the panel in compact state, so a notchless Mac would
        // have no visible compact Island at all. The notch style falls back to
        // a 300 pt top-center bar on notchless screens — the micro-bar we want.
        let notch = DynamicNotch(
            hoverBehavior: [.keepVisible],
            style: .notch,
            expanded: { ExpandedContentView(model: viewModel) },
            compactLeading: { CompactLeadingView() },
            compactTrailing: { CompactTrailingView(model: viewModel) }
        )
        self.notch = notch
        await notch.compact()

        store.$sessions
            .throttle(for: refreshInterval, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] sessions in
                MainActor.assumeIsolated {
                    self?.sessionsDidChange(sessions)
                }
            }
            .store(in: &cancellables)

        notch.$isHovering
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] hovering in
                MainActor.assumeIsolated {
                    self?.hoverDidChange(hovering)
                }
            }
            .store(in: &cancellables)

        // Quotas (issue #9): global gauges + per-Session context, throttled
        // like the sessions (the statusline fires on every UI refresh).
        quotaStore.$quotas
            .removeDuplicates()
            .throttle(for: refreshInterval, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] quotas in
                MainActor.assumeIsolated {
                    self?.quotasDidChange(quotas)
                }
            }
            .store(in: &cancellables)

        quotaStore.$contextBySession
            .removeDuplicates()
            .throttle(for: refreshInterval, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] context in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshCards()
                    if !context.isEmpty {
                        self.log("context: \(Self.contextTrace(for: context))")
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func sessionsDidChange(_ sessions: [Session]) {
        viewModel.compactSprites = Self.compactSprites(for: sessions)
        viewModel.compactTone = Self.compactTone(for: sessions)
        viewModel.cards = sessions.map { self.card(for: $0) }
        log("sessions: \(Self.sessionsTrace(for: sessions))")
        log("sprites: \(Self.spritesTrace(for: viewModel.compactSprites))")

        let newlyEnded = sessions.filter {
            $0.state == .ended && !knownEndedSessionIDs.contains($0.id)
        }
        knownEndedSessionIDs = Set(sessions.filter { $0.state == .ended }.map(\.id))

        let newlyWaiting = sessions.filter {
            $0.state == .waiting && !knownWaitingSessionIDs.contains($0.id)
        }
        knownWaitingSessionIDs = Set(sessions.filter { $0.state == .waiting }.map(\.id))

        // A blocked agent matters more than a finished one: same priority as
        // the Liseré.
        if let session = newlyWaiting.last ?? newlyEnded.last {
            peek(for: session)
        }
    }

    // MARK: - Click-to-focus (issue #10)

    /// A card (or the Peek) was clicked: acknowledge that Session and bring
    /// its terminal frontmost. The Island itself never becomes active (the
    /// panel is non-activating).
    func cardActivated(sessionID: String) {
        let session = store.sessions.first { $0.id == sessionID }
        store.acknowledge(sessionID: sessionID)
        log("card activated: \(sessionID) → focus terminal \(session?.terminal ?? "default")")
        focusTerminal?(session?.terminal)
    }

    // MARK: - Quotas (issue #9)

    private func card(for session: Session) -> SessionCard {
        SessionCard(
            session: session,
            contextUsedPercentage: quotaStore.contextBySession[session.id]
        )
    }

    /// Rebuilds the cards without re-tracing the sessions (context refresh).
    private func refreshCards() {
        viewModel.cards = store.sessions.map { self.card(for: $0) }
    }

    private func quotasDidChange(_ quotas: Quotas?) {
        viewModel.quotaGauges = quotas.map(QuotaGauge.gauges(for:)) ?? []
        log("quotas: \(quotas.map(Self.quotasTrace(for:)) ?? "hidden")")
    }

    /// Compact stdout trace of the global Quotas, so agentic tests can assert
    /// the gauges state-first ("none" when no window was reported).
    static func quotasTrace(for quotas: Quotas) -> String {
        var parts: [String] = []
        if let fiveHour = quotas.fiveHour {
            parts.append("5h=\(fiveHour.usedPercentage)%")
            if let resetsAt = fiveHour.resetsAt {
                parts.append("reset=\(Int(resetsAt.timeIntervalSince1970))")
            }
        }
        if let sevenDay = quotas.sevenDay {
            parts.append("7d=\(sevenDay.usedPercentage)%")
        }
        return parts.isEmpty ? "none" : parts.joined(separator: " ")
    }

    /// Stdout trace of the per-Session context usage, sorted for stability.
    static func contextTrace(for context: [String: Double]) -> String {
        context.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)%" }
            .joined(separator: " ")
    }

    // MARK: - Extended mode (hover only)

    func hoverDidChange(_ hovering: Bool) {
        if hovering {
            peekTask?.cancel()
            mode = .expandedHover
            viewModel.showCards = true
            // Hovering the Island is an Acknowledgement (issue #8): the user
            // has seen the pending states, the Liseré goes out.
            store.acknowledgeAll()
            log("expanded on hover: \(viewModel.cards.count) session card(s), acknowledged all")
            Task { [weak self] in
                await self?.notch?.expand()
            }
        } else if mode == .expandedHover {
            mode = .compact
            viewModel.showCards = false
            log("hover ended, folded back to compact")
            Task { [weak self] in
                await self?.notch?.compact()
            }
        }
    }

    // MARK: - Peek

    /// Expands the Island for a short while, then folds back to compact.
    /// Never fights the Extended mode: while hovered, no Peek.
    private func peek(for session: Session) {
        guard mode != .expandedHover else { return }
        viewModel.peekText = Self.peekText(for: session)
        viewModel.peekSessionID = session.id

        peekTask?.cancel()
        mode = .peek
        peekTask = Task { [weak self, peekDuration] in
            guard let self, let notch = self.notch else { return }
            log("peek shown: \(self.viewModel.peekText)")
            await notch.expand()
            try? await Task.sleep(for: peekDuration)
            guard !Task.isCancelled, self.mode == .peek else { return }
            self.mode = .compact
            await notch.compact()
            log("peek folded back to compact")
        }
    }

    /// Timestamped stdout trace of the Island lifecycle, so agentic tests can
    /// assert the peek/hover behavior state-first (the pixels are checked
    /// visually).
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("island: [\(timestamp)] \(message)")
    }

    /// One line per throttled refresh (never one per event): lets agentic
    /// tests follow the Session lifecycle — and the throttling — from stdout.
    static func sessionsTrace(for sessions: [Session]) -> String {
        guard !sessions.isEmpty else { return "none" }
        return sessions
            .map { session in
                var parts = "\(session.projectName)[\(session.id)]=\(session.state)"
                if let tool = session.currentTool {
                    parts += "(\(tool))"
                }
                // Active subagents (#31): a Session with one is never terminée —
                // surfaced here so agentic tests can assert it from stdout.
                if session.activeSubagentCount > 0 {
                    parts += "×\(session.activeSubagentCount)sub"
                }
                if session.lastSummary != nil {
                    parts += "+summary"
                }
                return parts
            }
            .joined(separator: " ")
    }

    /// Tint of the compact bar: mirrors the most pressing Session state.
    enum CompactTone: Equatable {
        case neutral
        /// A Session waits on the user (orange, wins over everything).
        case waiting
        /// A Session finished its turn (green).
        case finished
    }

    /// What the Peek announces for a marking event on a Session: the waiting
    /// call to action, or the first line of the turn summary (ADR-0002, falls
    /// back to the bare "terminé" when the transcript had nothing usable).
    static func peekText(for session: Session) -> String {
        session.state == .waiting
            ? "\(session.projectName) ? attend une réponse"
            : SessionCard.peekLine(
                project: session.projectName,
                summaryText: session.lastSummary?.text
            )
    }

    /// Orange when a Session waits, green when one finished, neutral
    /// otherwise — same priority as the Liseré.
    static func compactTone(for sessions: [Session]) -> CompactTone {
        if sessions.contains(where: { $0.state == .waiting }) { return .waiting }
        if sessions.contains(where: { $0.state == .ended }) { return .finished }
        return .neutral
    }

    /// One Sprite per Session (issue #11) — the compact bar mirrors the
    /// session list, each state encoded by the bot's animation.
    static func compactSprites(for sessions: [Session]) -> [CompactSprite] {
        sessions.map {
            CompactSprite(id: $0.id, animation: SpriteAnimation.animation(for: $0.state))
        }
    }

    /// Stdout trace of the compact Sprites, so agentic tests can assert the
    /// state → animation mapping without looking at pixels.
    static func spritesTrace(for sprites: [CompactSprite]) -> String {
        guard !sprites.isEmpty else { return "none" }
        return sprites.map(\.animation.rawValue).joined(separator: " ")
    }
}

/// One Sprite slot of the compact bar: which Session, which animation.
struct CompactSprite: Identifiable, Equatable {
    let id: String
    let animation: SpriteAnimation
}

/// Observable UI state: what the compact bar and the expanded content show.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published var peekText: String = ""
    /// Session announced by the current Peek: clicking the Peek activates it.
    @Published var peekSessionID: String?
    /// One pixel-art Sprite per live Session (issue #11).
    @Published var compactSprites: [CompactSprite] = []
    @Published var compactTone: IslandController.CompactTone = .neutral
    /// True while the Island is expanded by hover (Extended mode, cards);
    /// false when an expansion shows a Peek.
    @Published var showCards: Bool = false
    @Published var cards: [SessionCard] = []
    /// Global Quotas gauges (5 h / 7 d); empty = hidden (no rate limits
    /// reported yet — issue #9, never a misleading zero).
    @Published var quotaGauges: [QuotaGauge] = []
    /// Click-to-focus: set by the controller, called by card/Peek taps.
    var activateSession: ((String) -> Void)?
}

/// Expanded content: Session cards in Extended mode (hover), Peek text
/// otherwise.
struct ExpandedContentView: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        if model.showCards {
            SessionCardsView(model: model)
        } else {
            PeekView(model: model)
        }
    }
}

struct SessionCardsView: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.cards.isEmpty {
                Text("aucune session")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.cards) { card in
                SessionCardView(card: card)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.activateSession?(card.id)
                    }
            }
            // Quotas (issue #9): global gauges at the foot of the panel,
            // only when the statusline reported rate limits.
            if !model.quotaGauges.isEmpty {
                QuotaGaugesView(gauges: model.quotaGauges)
            }
        }
        .padding(12)
        .frame(maxWidth: 340)
    }
}

struct SessionCardView: View {
    let card: SessionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Pixel-art state glyph (issue #11): the bot screen's glyph
                // alone, same palette and pace as the compact Sprites.
                SpriteView(sheet: .glyphs, imageName: "glyphs", animation: card.animation)
                Text(card.project)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(card.stateLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let start = card.turnStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(SessionCard.durationText(
                            seconds: max(0, Int(context.date.timeIntervalSince(start)))
                        ))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if let location = card.location {
                Text(location)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            if let prompt = card.lastPrompt {
                Text("« \(prompt) »")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let tool = card.currentTool {
                Text("outil : \(tool)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            if let summary = card.summaryText {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let facts = card.summaryFacts {
                Text(facts)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Quotas (issue #9): per-Session context usage from the tee.
            if let context = card.contextLabel {
                Text(context)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.08))
        )
        .foregroundStyle(.white)
    }
}

struct PeekView: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        Text(model.peekText)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                if let sessionID = model.peekSessionID {
                    model.activateSession?(sessionID)
                }
            }
    }
}

/// The isle logo, pixel-art like the bots (validated with planche C).
struct CompactLeadingView: View {
    var body: some View {
        SpriteView(sheet: .isle, imageName: "isle", animation: .working)
    }
}

/// One animated Sprite per Session (issue #11). The sprites carry the state
/// tints themselves (green check, orange question mark); the #8 Compact tone
/// remains as a soft halo behind the row, same priority as the Liseré.
struct CompactTrailingView: View {
    @ObservedObject var model: IslandViewModel

    private var glow: Color {
        switch model.compactTone {
        case .neutral: .clear
        case .waiting: .orange
        case .finished: .green
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            if model.compactSprites.isEmpty {
                Text("–")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }
            ForEach(model.compactSprites) { sprite in
                SpriteView(sheet: .bot, imageName: "bot", animation: sprite.animation)
            }
        }
        .shadow(color: glow, radius: 3)
    }
}
