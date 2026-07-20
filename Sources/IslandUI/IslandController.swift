import AppKit
import Combine
import DynamicNotchKit
import IslandStore
import SwiftUI

/// Drives the Island (ADR-0007): a `.floating` panel that is **Masqué** (nothing
/// on screen) by default — even while Sessions work — and only ever surfaces by:
/// - a ~2.5 s **Peek** when a Session waits or finishes its turn, then back to
///   Masqué (the persistence of attention is carried by the Liseré, not the Peek);
/// - a deliberate **Reveal** — the global mouse monitor detects the top-edge
///   gesture via the pure ``shouldReveal(at:in:sessionCount:)`` and deploys the
///   **Étendu** (one card per Session), which the native `.keepVisible` hover
///   keeps open and which recedes to Masqué when the pointer leaves.
///
/// The Island never expands on its own outside those two paths, and neither the
/// Reveal nor the hover acknowledges anything (looking ≠ treating): Acknowledgement
/// happens one Session at a time via click-to-focus (#10) or terminal refocus.
/// The panel is non-activating (DynamicNotchKit uses a `.nonactivatingPanel`), so
/// it never steals focus from the terminal.
///
/// Depends only on the generic session store (ADR-0004). Store updates are
/// throttled before touching the view model: PreToolUse/PostToolUse arrive at
/// high rate and must not trigger one render each.
@MainActor
public final class IslandController {
    /// The Island's visibility machine (ADR-0007, issue #53). The floating
    /// panel is hidden by default; it only surfaces for a transient Peek or a
    /// deliberate Reveal, then recedes back to Masqué.
    private enum Mode {
        /// Masqué: nothing on screen, even while Sessions work.
        case hidden
        /// Peek: transient surface on a marking event, then back to Masqué.
        case peek
        /// Étendu: the revealed cards, kept open by hover, folds on pointer exit.
        case expanded
    }

    private let store: SessionStore
    private let quotaStore: QuotaStore
    /// Click-to-focus (issue #10): brings the Session's terminal frontmost.
    /// Injected so the UI never depends on a concrete terminal module.
    private let focusTerminal: ((String?) -> Void)?
    /// Re-reads Session titles on Extended open (issue #32). Injected so the UI
    /// never learns where titles come from (a `/rename` on an idle/ended Session
    /// fires no hook; hovering must still show the new title). ADR-0004: the
    /// transcript lives behind the adapter, the controller only triggers.
    private let refreshTitles: (() -> Void)?
    private let viewModel = IslandViewModel()
    private var notch: DynamicNotch<ExpandedContentView, EmptyView, EmptyView>?
    private var cancellables: Set<AnyCancellable> = []
    private var knownEndedSessionIDs: Set<String> = []
    private var knownWaitingSessionIDs: Set<String> = []
    private var peekTask: Task<Void, Never>?
    /// Anti-flicker grace before the revealed Island recedes to Masqué.
    private var recedeTask: Task<Void, Never>?
    private var mode: Mode = .hidden

    /// How long a Peek stays on screen before folding back to Masqué.
    private let peekDuration: Duration = .seconds(2.5)
    /// Grace delay before a hover-off recedes the Étendu to Masqué: bridges the
    /// brief gap between the top-edge gesture and the pointer landing on the
    /// panel, so the Island does not flicker shut mid-reveal.
    private let recedeGrace: Duration = .milliseconds(300)
    /// Width of the centred top-edge band that triggers a Reveal (~webcam),
    /// used by the pure ``shouldReveal(at:in:sessionCount:)`` (issue #53).
    public static let revealBandWidth: CGFloat = 280
    /// How close to the very top edge the cursor must be pinned to count as the
    /// deliberate "hard edge" gesture (a couple of points of hardware slack).
    private static let edgeTolerance: CGFloat = 2
    /// Width of the keep-alive band around the reveal, used by the geometric
    /// recede (issue #60). Wider than ``revealBandWidth`` (matches the panel's
    /// `maxWidth`) so there is a horizontal hysteresis seam between "reveal" and
    /// "recede": a cursor oscillating at the band edge triggers neither.
    public static let recedeBandWidth: CGFloat = 340
    /// How far below the top edge the cursor may sit and still keep the Étendu
    /// alive (issue #60): covers the deployed panel's height so approaching or
    /// loitering over it never arms a recede — only clearly dropping away does.
    private static let recedeKeepAliveDepth: CGFloat = 220
    /// Store updates are coalesced to at most one UI refresh per interval.
    private let refreshInterval: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(200)

    public init(
        store: SessionStore,
        quotaStore: QuotaStore = QuotaStore(),
        focusTerminal: ((String?) -> Void)? = nil,
        refreshTitles: (() -> Void)? = nil
    ) {
        self.store = store
        self.quotaStore = quotaStore
        self.focusTerminal = focusTerminal
        self.refreshTitles = refreshTitles
        viewModel.activateSession = { [weak self] sessionID in
            self?.cardActivated(sessionID: sessionID)
        }
    }

    /// Starts reacting to session changes. The Island stays Masqué (nothing on
    /// screen) until a Peek or a Reveal surfaces it (ADR-0007, issue #53).
    public func activate() async {
        let viewModel = viewModel
        // `.floating` (ADR-0007): the Island is masqué by default on a notchless
        // Mac. In DynamicNotchKit the floating style *hides* the panel on
        // `compact()`, so there is no always-visible micro-bar and the compact
        // views would never render — the panel only exists during a Peek or a
        // Reveal. The compact-less initializer disables both compact slots
        // (issue #55). Its `.keepVisible` hover keeps the Étendu open while the
        // pointer is on it.
        let notch = DynamicNotch(
            hoverBehavior: [.keepVisible],
            style: .floating,
            expanded: { ExpandedContentView(model: viewModel) }
        )
        self.notch = notch
        // No initial surface: Masqué is the resting state.
        mode = .hidden
        log("masqué (au repos)")

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
        setCards(from: sessions)
        log("sessions: \(Self.sessionsTrace(for: sessions))")

        let newlyEnded = sessions.filter {
            $0.state == .ended && !knownEndedSessionIDs.contains($0.id)
        }
        knownEndedSessionIDs = Set(sessions.filter { $0.state == .ended }.map(\.id))

        let newlyWaiting = sessions.filter {
            $0.state == .waiting && !knownWaitingSessionIDs.contains($0.id)
        }
        knownWaitingSessionIDs = Set(sessions.filter { $0.state == .waiting }.map(\.id))

        // A blocked agent matters more than a finished one: the Peek picks the
        // most pressing newly-marking Session by the shared Priorité d'état.
        if let session = Self.mostPressingForPeek(newlyWaiting + newlyEnded) {
            peek(for: session)
        }
    }

    /// Orders the Extended cards by **Priorité d'état** (issue #44): the shared
    /// ``SessionState/priorityRank`` first (waiting > terminé > working > idle),
    /// then a per-group recency tie-break on `lastActivityAt` — `waiting` oldest
    /// first (anti-oubli: what has waited longest is the most urgent), every
    /// other group freshest first (the latest result on top, the rest below the
    /// fold). A final `id` tie-break makes the order fully deterministic, so a
    /// refresh never reshuffles equal cards (no jitter); the reordering itself
    /// is animated by card `id` in the view.
    static func sortedByStatePriority(_ sessions: [Session]) -> [Session] {
        sessions.sorted { lhs, rhs in
            let lhsRank = lhs.state.priorityRank
            let rhsRank = rhs.state.priorityRank
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.lastActivityAt != rhs.lastActivityAt {
                // waiting: oldest first (ascending); every other group: freshest
                // first (descending).
                return lhs.state == .waiting
                    ? lhs.lastActivityAt < rhs.lastActivityAt
                    : lhs.lastActivityAt > rhs.lastActivityAt
            }
            return lhs.id < rhs.id
        }
    }

    /// The Session a Peek announces among the newly-marking ones: the most
    /// pressing state present (shared Priorité d'état — waiting outranks terminé)
    /// and, within that group, the latest to have arrived. `nil` when nothing is
    /// newly marking. Sources the waiting > terminé order from the shared rank
    /// instead of hardcoding it.
    static func mostPressingForPeek(_ sessions: [Session]) -> Session? {
        guard let topRank = sessions.map(\.state.priorityRank).min() else { return nil }
        return sessions.last { $0.state.priorityRank == topRank }
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

    /// Rebuilds the cards without re-tracing the sessions (context refresh),
    /// keeping the same Priorité d'état order as the main refresh so a context
    /// update never reshuffles the panel.
    private func refreshCards() {
        setCards(from: store.sessions)
    }

    /// Publishes the cards in Priorité d'état order (issue #44), animating the
    /// reordering so a Session changing rank slides into place instead of
    /// snapping. The order is deterministic (see ``sortedByStatePriority(_:)``),
    /// so equal cards never reshuffle and the animation only fires on a real
    /// rank/recency change.
    private func setCards(from sessions: [Session]) {
        let cards = Self.sortedByStatePriority(sessions).map { self.card(for: $0) }
        withAnimation(.default) {
            viewModel.cards = cards
        }
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

    // MARK: - Reveal / Extended mode (issue #53)

    /// Deliberate Reveal from the global mouse monitor: the cursor was pinned to
    /// the top-centre edge (``shouldReveal(at:in:sessionCount:)`` already vetted
    /// the geometry and the ≥1-Session rule), so deploy the Étendu. Works at any
    /// time — rest or waiting — and over a full-screen app (the panel is
    /// `.screenSaver` + `.canJoinAllSpaces`). Never acknowledges: looking ≠
    /// treating (ADR-0007).
    public func reveal() {
        expandToExtended(trigger: "révélation")
    }

    /// Geometric recede fallback (issue #60): the global monitor reports the
    /// cursor left the reveal band (``shouldRecede(at:in:)``) while the Étendu is
    /// open and the pointer is *not* on the panel — the case the native hover-off
    /// misses, because the panel deploys around the cursor at the edge and no
    /// `mouseEntered` ever fired. Arms the same anti-flicker recede, once: a
    /// pending grace is left running (re-entering the band or the panel is what
    /// cancels it), so continuous motion away does not keep restarting it.
    public func recedeIfClearOfPanel() {
        guard mode == .expanded, notch?.isHovering != true, recedeTask == nil else { return }
        scheduleRecede()
    }

    /// Test seam (issue #60): whether the Étendu is currently deployed, so the
    /// recede tests can assert the fold without reaching into the private `mode`.
    var isExtendedDeployed: Bool { mode == .expanded }

    /// Whether the top-edge gesture should Reveal the Island: cursor pinned to
    /// the top edge (Cocoa `maxY`) *and* inside the centred ~280 pt band near
    /// the webcam *and* at least one Session exists. Pure — the `NSEvent`
    /// monitor is a thin shell delegating every decision here (issue #53).
    public static func shouldReveal(
        at mouseLocation: CGPoint,
        in screenFrame: CGRect,
        sessionCount: Int
    ) -> Bool {
        guard sessionCount >= 1 else { return false }
        let atTopEdge = mouseLocation.y >= screenFrame.maxY - edgeTolerance
        let inCentreBand = abs(mouseLocation.x - screenFrame.midX) <= revealBandWidth / 2
        return atTopEdge && inCentreBand
    }

    /// Whether the cursor has clearly left the reveal — the geometric recede of
    /// issue #60. True when the pointer either drops below the keep-alive depth
    /// or moves out of the wider recede band. Pure, and deliberately loose (a
    /// hysteresis seam sits between this and ``shouldReveal(at:in:sessionCount:)``)
    /// so brief oscillation around the edge folds nothing. The `NSEvent` monitor
    /// asks this only while the Étendu is open and the panel is not being hovered
    /// (the native hover is the authority on "the cursor is on the panel").
    public static func shouldRecede(
        at mouseLocation: CGPoint,
        in screenFrame: CGRect
    ) -> Bool {
        let depthBelowEdge = screenFrame.maxY - mouseLocation.y
        let droppedBelowKeepAlive = depthBelowEdge > recedeKeepAliveDepth
        let outsideRecedeBand = abs(mouseLocation.x - screenFrame.midX) > recedeBandWidth / 2
        return droppedBelowKeepAlive || outsideRecedeBand
    }

    /// Native DynamicNotchKit hover, live only while a panel exists (`state !=
    /// .hidden`). Hovering a Peek promotes it to the Étendu; hovering the
    /// revealed panel keeps it open; leaving it recedes to Masqué after a grace
    /// delay. Never acknowledges (ADR-0007).
    func hoverDidChange(_ hovering: Bool) {
        if hovering {
            expandToExtended(trigger: "révélation (survol)")
        } else if mode == .expanded {
            scheduleRecede()
        }
    }

    /// Deploys the Étendu (cards), idempotent: a second trigger while already
    /// expanded just cancels a pending recede. Re-reads titles on open (#32) so
    /// a `/rename` on an idle/ended Session — which fired no hook — shows now.
    private func expandToExtended(trigger: String) {
        peekTask?.cancel()
        recedeTask?.cancel()
        recedeTask = nil
        guard mode != .expanded else { return }
        mode = .expanded
        refreshTitles?()
        viewModel.showCards = true
        log("\(trigger): \(viewModel.cards.count) session card(s) [\(Self.cardsTrace(for: viewModel.cards))]")
        Task { [weak self] in
            await self?.notch?.expand()
        }
    }

    /// Compact stdout trace of the deployed cards **in Priorité d'état order**
    /// (issue #44), so an agentic test can assert the ordering state-first when
    /// the Étendu deploys — the card order has no other observable signal (the
    /// SwiftUI order is not otherwise reachable, and the sessions trace follows
    /// store insertion, not the sort).
    static func cardsTrace(for cards: [SessionCard]) -> String {
        cards.map { "\($0.project)[\($0.id)]=\($0.stateLabel)" }.joined(separator: " > ")
    }

    /// Recede the revealed Island to Masqué after a short anti-flicker grace, so
    /// a pointer briefly leaving and re-entering the panel does not blink it shut.
    private func scheduleRecede() {
        recedeTask?.cancel()
        recedeTask = Task { [weak self, recedeGrace] in
            try? await Task.sleep(for: recedeGrace)
            guard let self, !Task.isCancelled, self.mode == .expanded,
                self.notch?.isHovering != true
            else { return }
            self.mode = .hidden
            self.viewModel.showCards = false
            self.log("masqué (curseur quitte le panneau)")
            await self.notch?.hide()
        }
    }

    // MARK: - Peek

    /// Surfaces the Island in a transient Peek, then recedes to Masqué. Never
    /// fights the Étendu: while revealed, no Peek (ADR-0007, issue #53).
    private func peek(for session: Session) {
        guard mode != .expanded else { return }
        viewModel.peekText = Self.peekText(for: session)
        viewModel.peekAnimation = Self.peekAnimation(for: session)
        viewModel.peekSessionID = session.id
        // A Peek shows the peek text, not the cards, whatever the last Reveal left.
        viewModel.showCards = false

        peekTask?.cancel()
        recedeTask?.cancel()
        mode = .peek
        peekTask = Task { [weak self, peekDuration] in
            guard let self, let notch = self.notch else { return }
            log("peek: \(self.viewModel.peekText)")
            await notch.expand()
            try? await Task.sleep(for: peekDuration)
            guard !Task.isCancelled, self.mode == .peek else { return }
            self.mode = .hidden
            await notch.hide()
            log("masqué (peek terminé)")
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
                // Live Sous-agents (#48), read from the Stop's background_tasks:
                // a Session with one is never terminée. Surfaced on stdout so the
                // agentic FP can assert the count was parsed (state=running +
                // ×Nsub proves the gate engaged), the production trace of the
                // decoded count — distinct from any capture instrumentation.
                if session.activeSubagentCount > 0 {
                    parts += " ×\(session.activeSubagentCount)sub"
                }
                if session.lastSummary != nil {
                    parts += "+summary"
                }
                return parts
            }
            .joined(separator: " ")
    }

    /// What the Peek announces for a marking event on a Session: the waiting
    /// call to action, or the first line of the turn summary (ADR-0002, falls
    /// back to the bare "terminé" when the transcript had nothing usable).
    static func peekText(for session: Session) -> String {
        session.state == .waiting
            ? SessionCard.waitingPeekLine(
                project: session.projectName,
                questionText: session.lastSummary?.text
            )
            : SessionCard.peekLine(
                project: session.projectName,
                summaryText: session.lastSummary?.text
            )
    }

    /// The Sprite the Peek shows for a marking event (issue #55): the Session's
    /// mascot, its animation encoding the state through the same mapping the
    /// Extended cards use, so the transient Peek and the cards speak the same
    /// visual language.
    static func peekAnimation(for session: Session) -> SpriteAnimation {
        SpriteAnimation.animation(for: session.state)
    }
}

/// Observable UI state: what the Peek and the expanded content show.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published var peekText: String = ""
    /// Animation of the Peek's Sprite (issue #55): the mascot of the Session the
    /// Peek announces, its animation encoding the state.
    @Published var peekAnimation: SpriteAnimation = .working
    /// Session announced by the current Peek: clicking the Peek activates it.
    @Published var peekSessionID: String?
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

    /// Fraction of the screen height the Extended list may fill before it starts
    /// to scroll (#43). Kept well under the vendored half-screen window borne
    /// (`DynamicNotch` sizes its panel to `screen.frame.height / 2`), so this
    /// content cap — not the window — is what bounds a crowded list.
    static let maxHeightFraction: CGFloat = 0.25

    /// The panel height for a given content and screen: hug the content below
    /// the cap (no empty space with 1–2 Sessions), clamp to ~1/4 of the screen
    /// above it so the overflow scrolls. Pure, so the arithmetic is pinned by a
    /// unit test while the scrolling itself is verified visually.
    static func cappedHeight(contentHeight: CGFloat, screenHeight: CGFloat) -> CGFloat {
        min(contentHeight, screenHeight * maxHeightFraction)
    }

    /// Measured intrinsic height of the card list, fed by a background
    /// `GeometryReader`. Zero until the first layout pass — the panel then stays
    /// intrinsic so the vendored `.fixedSize()` wrap never collapses it to
    /// nothing before the first measurement lands.
    @State private var contentHeight: CGFloat = 0

    /// ~1/4 of the current screen height, mirroring the vendored borne's use of
    /// `frame` (not `visibleFrame`) on the first screen. Falls back to a sane
    /// value when no screen is reported.
    private var screenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 900
    }

    var body: some View {
        ScrollView(.vertical) {
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
                // only when the statusline reported rate limits. In v1 they
                // scroll with the list (#43).
                if !model.quotaGauges.isEmpty {
                    QuotaGaugesView(gauges: model.quotaGauges)
                }
            }
            .padding(12)
            .frame(maxWidth: 340)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, newValue in
                            contentHeight = newValue
                        }
                }
            )
        }
        // Hug the content until it would exceed ~1/4 of the screen, then cap and
        // let the overflow scroll (#43). Standard macOS overlay scrollers — no
        // permanent indicator. Only the height is constrained: the width keeps
        // hugging its content up to 340 pt, unchanged.
        .frame(height: contentHeight == 0
            ? nil
            : Self.cappedHeight(contentHeight: contentHeight, screenHeight: screenHeight))
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
                // Session title on top (issue #32), reflecting /rename; the
                // project path sits underneath. A long title truncates cleanly
                // on the tail so the state label stays visible.
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
            // Discreet Sous-agent tally (issue #48, Q6): "⋯ N sous-agents en
            // cours" — shown only while at least one runs.
            if let subagents = card.subagentsLabel {
                Text("⋯ \(subagents)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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

/// The transient Peek (issue #55): the Session's Sprite — its animation encodes
/// the state (green check when finished, blinking question when waiting) — next
/// to the announcement text, the same visual language as the Extended cards.
/// Stays clickable (click-to-focus, #10) over the whole surface.
struct PeekView: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        HStack(spacing: 8) {
            SpriteView(sheet: .bot, imageName: "bot", animation: model.peekAnimation)
            Text(model.peekText)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
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
