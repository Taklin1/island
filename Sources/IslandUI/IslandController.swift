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
    /// Click-to-focus (issues #10, #36): brings the Session's terminal
    /// frontmost — given its terminal identifier and its cwd, so the focuser
    /// can target the Session's exact Ghostty window when it is a certain
    /// target (and degrade to the whole app otherwise). Injected so the UI
    /// never depends on a concrete terminal module.
    private let focusTerminal: ((_ terminal: String?, _ cwd: String?) -> Void)?
    /// Answer-by-injection (issues #27/#81): given a Session's cwd and the
    /// chosen AskUserQuestion option index, targets that Session's Ghostty
    /// window and injects the keystroke **only** if the target is certain and
    /// its delivery is verified at the instant of the post (#81), returning
    /// whether the keystroke was actually posted. `false` means nothing was
    /// posted (uncertain target, no Accessibility permission, unverified
    /// delivery) and the controller degrades to Click-to-focus — the
    /// "working" feedback is never shown for a keystroke that did not go out.
    /// Injected as a plain closure so the UI never imports the Focus/AX module,
    /// and so the real injection — proven only on the packaged app (spike #25) —
    /// stays entirely outside the controller. Async because the delivery
    /// verification awaits the terminal's activation.
    private let injectAnswer: ((_ cwd: String?, _ optionIndex: Int) async -> Bool)?
    /// Re-reads Session titles on Extended open (issue #32). Injected so the UI
    /// never learns where titles come from (a `/rename` on an idle/ended Session
    /// fires no hook; hovering must still show the new title). ADR-0004: the
    /// transcript lives behind the adapter, the controller only triggers.
    private let refreshTitles: (() -> Void)?
    private let viewModel = IslandViewModel()
    private var notch: DynamicNotch<ExpandedContentView, EmptyView, EmptyView>?
    private var cancellables: Set<AnyCancellable> = []
    /// Announcement memory (#132): Sessions whose "terminé" was already
    /// announced (Peek fired or absorbed by a live surface) and not rearmed
    /// since. Unlike the pre-#132 per-state diff — recomputed from the current
    /// snapshot on every refresh, so a Session leaving then re-entering the
    /// state became "newly" marking again — this set PERSISTS across state
    /// flips: an ADR-0008 gate flip (terminé ↔ en cours) or an identical
    /// re-emission spaced beyond a Peek's life stays silent, the Liseré alone
    /// carrying the persistence of attention (ADR-0007). Only an
    /// Acknowledgement of the Session or a real new turn rearms the pair
    /// (see ``rearmAnnouncements(for:)``).
    private var announcedEndedSessionIDs: Set<String> = []
    /// Twin of ``announcedEndedSessionIDs`` for the "attend" marking state.
    private var announcedWaitingSessionIDs: Set<String> = []
    /// Last published snapshot of each Session (#132): what the rearm pass
    /// diffs against to observe an Acknowledgement (`needsAcknowledgement`
    /// true→false) or a real new turn (`lastPrompt`/`turnStartedAt` moved)
    /// from the controller's snapshot-only view of the store.
    private var lastSnapshotByID: [String: Session] = [:]
    /// Sessions whose answer delivery is currently in flight (#81): guards a
    /// second tap during the ~500 ms verification await.
    private var answerInFlight: Set<String> = []
    /// Recede timer of a live Peek (#99): armed on deploy and re-armed on every
    /// coalesced marking event, so a burst is ONE continuous surface that only
    /// folds back to Masqué a Peek's duration after the *last* event.
    private var peekTask: Task<Void, Never>?
    /// Anti-flicker grace before the revealed Island recedes to Masqué.
    private var recedeTask: Task<Void, Never>?
    /// Pending press dwell (#130): armed when the cursor pins the top-centre
    /// band, cancelled (re-armed for the next press) if it leaves before term.
    private var dwellTask: Task<Void, Never>?
    /// Post-fold cooldown timer (#130): while it runs, no re-Révélation — a
    /// frame-level dip off the edge during the fold gesture re-arms nothing.
    private var cooldownTask: Task<Void, Never>?
    /// Whether the post-fold cooldown window is still open (#130).
    private var recedeCooldownActive = false
    /// Whether the Révélation is armed (#130): true initially and once the
    /// cursor has been seen OFF the top edge since the last fold of the Étendu.
    /// Scrubbing along the edge after a fold never re-arms — leaving then coming
    /// back to press is the new intention that does.
    private var revealArmed = true
    /// Last cursor sample the monitor forwarded (#130): lets the hover-off path
    /// tell a real leave from the spurious hover flip the deploy animation fires
    /// while the cursor stays pinned at the edge (the panel slides under it, no
    /// mouse event follows to cancel a wrongly-armed grace).
    private var lastMouseSample: (location: CGPoint, screenFrame: CGRect)?
    /// Last displayed height of the Étendu's content the view reported (#141):
    /// the card list as actually rendered — measured by the view's
    /// `GeometryReader` and already capped to ~1/4 of the screen — so the
    /// keep-alive depth can cover the *real* panel. `nil` until the first
    /// layout pass of the first deployment reports in; the derivation then
    /// falls back to the conservative ``fallbackRecedeKeepAliveDepth``.
    private var measuredPanelHeight: CGFloat?
    private var mode: Mode = .hidden
    /// The marking (Session id + state) the current Peek announces (#99). A new
    /// marking event that matches it is a redundant re-announcement (an
    /// ADR-0008 gate flip, a statusline re-emit) and updates nothing; a
    /// different one swaps the Sprite/text in place — never a teardown+redeploy.
    /// `nil` while Masqué.
    private var peekMarking: (id: String, state: SessionState)?
    /// How many times a *new* Peek window was surfaced from Masqué (#99). A
    /// burst of marking events must coalesce into ONE continuous surface, so
    /// this stays at 1 across the whole burst — the anti-pump invariant the unit
    /// tests assert (the window monte/descend has no other reachable signal
    /// without a real panel).
    private(set) var peekSurfaceCount = 0

    /// How long a Peek stays on screen before folding back to Masqué. Injectable
    /// so the coalescence tests can drive the recede deterministically (#99).
    private let peekDuration: Duration
    /// Grace delay before a hover-off recedes the Étendu to Masqué: bridges the
    /// brief gap between the top-edge gesture and the pointer landing on the
    /// panel, so the Island does not flicker shut mid-reveal. Injectable (twin of
    /// ``peekDuration``) so the recede tests can drive the fold deterministically
    /// without racing a fixed sleep against a real 300 ms grace (#109); stays
    /// 300 ms in production (anti-flicker unchanged, ADR-0007).
    private let recedeGrace: Duration
    /// How long the cursor must stay pressed against the top-centre edge before
    /// the Révélation deploys (#130): a quick pass through the band reveals
    /// nothing, only a held press does. Injectable (twin of ``recedeGrace``,
    /// `.zero` in tests) so the press settles deterministically via
    /// ``settleDwell()`` — never a fixed sleep (#109).
    private let dwellDuration: Duration
    /// How long after a fold of the Étendu (geometric or hover-off) the
    /// Révélation stays disarmed (#130), on top of the leave-the-edge re-arm: a
    /// frame-level dip off the edge during the fold gesture must not re-arm a
    /// rafale. Injectable (`.zero` in tests), settled via
    /// ``settleRecedeCooldown()``.
    private let recedeCooldown: Duration
    /// Width of the centred top-edge band that triggers a Reveal (~webcam),
    /// used by the pure ``shouldReveal(at:in:sessionCount:)`` (issue #53).
    public static let revealBandWidth: CGFloat = 280
    /// How close to the very top edge the cursor must be pinned to count as the
    /// deliberate "hard edge" gesture (a couple of points of hardware slack).
    private static let edgeTolerance: CGFloat = 2
    /// Max width of the Étendu's *content* column (the cards), the single source
    /// for the panel's `.frame(maxWidth:)` and the recede-band derivation (#130).
    static let extendedContentMaxWidth: CGFloat = 340
    /// Horizontal padding the vendored floating style adds around the content
    /// (`NotchlessView.swift` `.padding(20)` — revisit on a vendor update), so
    /// the *real* deployed panel is `extendedContentMaxWidth + 2 × this` wide.
    private static let floatingStylePadding: CGFloat = 20
    /// Guaranteed horizontal hysteresis beyond the real panel edge (#130): the
    /// keep-alive band must outreach the panel by a margin the cursor cannot sit
    /// on, so skimming the panel's outer edge never folds it under the pointer.
    private static let recedeHysteresisMargin: CGFloat = 40
    /// Width of the keep-alive band around the reveal, used by the geometric
    /// recede (issue #60). Derived from the panel's **real** width — content plus
    /// the vendored floating padding — plus the hysteresis margin on each side
    /// (#130): the old fixed 340 matched the content only, leaving ~20 pt on each
    /// side where the cursor was ON the panel yet outside the band (fold under
    /// the pointer). Wider than ``revealBandWidth``, so a horizontal hysteresis
    /// seam still sits between "reveal" and "recede".
    public static let recedeBandWidth: CGFloat =
        extendedContentMaxWidth + 2 * floatingStylePadding + 2 * recedeHysteresisMargin
    /// Conservative keep-alive depth while no panel height was measured yet
    /// (#141): the pre-#141 fixed depth, kept as the floor so the very first
    /// deployment (before the view's first layout reports a height) and a short
    /// panel (1–2 cards) behave exactly as before. The *live* depth is derived
    /// from the real panel height — see ``recedeKeepAliveDepth``.
    static let fallbackRecedeKeepAliveDepth: CGFloat = 220
    /// Store updates are coalesced to at most one UI refresh per interval.
    private let refreshInterval: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(200)

    public init(
        store: SessionStore,
        quotaStore: QuotaStore = QuotaStore(),
        focusTerminal: ((_ terminal: String?, _ cwd: String?) -> Void)? = nil,
        refreshTitles: (() -> Void)? = nil,
        injectAnswer: ((_ cwd: String?, _ optionIndex: Int) async -> Bool)? = nil,
        peekDuration: Duration = .seconds(2.5),
        recedeGrace: Duration = .milliseconds(300),
        dwellDuration: Duration = .milliseconds(120),
        recedeCooldown: Duration = .milliseconds(700)
    ) {
        self.store = store
        self.quotaStore = quotaStore
        self.focusTerminal = focusTerminal
        self.refreshTitles = refreshTitles
        self.injectAnswer = injectAnswer
        self.peekDuration = peekDuration
        self.recedeGrace = recedeGrace
        self.dwellDuration = dwellDuration
        self.recedeCooldown = recedeCooldown
        viewModel.activateSession = { [weak self] sessionID in
            self?.cardActivated(sessionID: sessionID)
        }
        viewModel.answerOption = { [weak self] sessionID, optionIndex in
            guard let self else { return }
            Task { await self.optionSelected(sessionID: sessionID, optionIndex: optionIndex) }
        }
        viewModel.panelHeightChanged = { [weak self] height in
            self?.panelHeightDidChange(height)
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

    /// The throttled sink handler: reconciles the cards and fires a Peek for the
    /// most pressing newly-marking Session. Internal (not private) so the
    /// coalescence tests (#99) can drive the exact burst sequence directly,
    /// bypassing the Combine throttle whose behaviour is orthogonal.
    func sessionsDidChange(_ sessions: [Session]) {
        setCards(from: sessions)
        log("sessions: \(Self.sessionsTrace(for: sessions))")

        rearmAnnouncements(for: sessions)

        // A marking Session is "newly" so only while its event still awaits
        // Acknowledgement (read-only — the exact predicate the Liseré renders,
        // `GlowColor.desired`; this NEVER writes `needsAcknowledgement`) and
        // while its (Session, state) pair is not in the announcement memory
        // (#132). The `needsAcknowledgement` guard is also what keeps the
        // rearm-by-Acknowledgement from announcing at the acknowledging
        // snapshot itself: the pair is cleared there, but the flag is false.
        let newlyEnded = sessions.filter {
            $0.state == .ended && $0.needsAcknowledgement
                && !announcedEndedSessionIDs.contains($0.id)
        }
        announcedEndedSessionIDs.formUnion(newlyEnded.map(\.id))

        let newlyWaiting = sessions.filter {
            $0.state == .waiting && $0.needsAcknowledgement
                && !announcedWaitingSessionIDs.contains($0.id)
        }
        announcedWaitingSessionIDs.formUnion(newlyWaiting.map(\.id))

        // A blocked agent matters more than a finished one: the Peek picks the
        // most pressing newly-marking Session by the shared Priorité d'état.
        if let session = Self.mostPressingForPeek(newlyWaiting + newlyEnded) {
            peek(for: session)
        }
    }

    /// The rearm pass of the announcement memory (#132): diffs each Session
    /// against its last published snapshot and forgets its announced pairs
    /// when either rearm the founder decisions retained fires —
    ///
    /// - **Acknowledgement**: `needsAcknowledgement` true→false, the one
    ///   observable every acknowledging path shares (card click, terminal
    ///   refocus, answer-by-injection `resumeAfterAnswer`);
    /// - **real new turn**: `lastPrompt` moved, or `turnStartedAt` moved to a
    ///   fresh non-nil start — markers only `promptSubmitted` (and the
    ///   answered-in-terminal resume) produce. The ADR-0008 gate flip touches
    ///   NEITHER (its `.running` keeps the ended turn's nil `turnStartedAt`
    ///   and never rewrites the prompt), so entering `.running` alone never
    ///   rearms — the central trap of #132. `lastSummary → nil` is
    ///   deliberately NOT used: a gate Stop whose transcript yields no summary
    ///   would fake it. The `lastPrompt` marker survives a throttle window
    ///   that coalesces prompt+Stop into one snapshot (the Stop never touches
    ///   the prompt).
    ///
    /// Departed Sessions (closed or purged) are forgotten entirely: a Session
    /// re-appearing later is a fresh announcement, as before #132.
    private func rearmAnnouncements(for sessions: [Session]) {
        for session in sessions {
            guard let previous = lastSnapshotByID[session.id] else { continue }
            let acknowledged = previous.needsAcknowledgement && !session.needsAcknowledgement
            let newRealTurn = session.lastPrompt != previous.lastPrompt
                || (session.turnStartedAt != nil && session.turnStartedAt != previous.turnStartedAt)
            if acknowledged || newRealTurn {
                announcedEndedSessionIDs.remove(session.id)
                announcedWaitingSessionIDs.remove(session.id)
            }
        }
        let liveIDs = Set(sessions.map(\.id))
        announcedEndedSessionIDs.formIntersection(liveIDs)
        announcedWaitingSessionIDs.formIntersection(liveIDs)
        lastSnapshotByID = Dictionary(
            sessions.map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )
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
        focusTerminal?(session?.terminal, session?.cwd)
    }

    // MARK: - Answer from the Island (issue #27)

    /// An AskUserQuestion option button was tapped: attempt a **safe-targeted**
    /// injection of that option's keystroke into the Session's terminal, and on
    /// any doubt degrade to Click-to-focus — never a keystroke in the wrong
    /// terminal (ADR-0009). Injection is attempted only while the Session is
    /// genuinely `.waiting` (a real event may have moved it between render and
    /// tap). On a **verified** delivery (#81: `injectAnswer` returns true only
    /// once the keystroke was actually posted to the vetted target) the Session
    /// resumes `.running`; otherwise the tap behaves exactly like a card tap
    /// (acknowledge + focus) — the card never lies about an answer going out.
    func optionSelected(sessionID: String, optionIndex: Int) async {
        // Re-entrance guard (#81): the delivery verification awaits the
        // terminal's activation (up to ~500 ms) — an impatient second tap on
        // the same card during that window must not fire a second keystroke.
        guard !answerInFlight.contains(sessionID) else { return }
        answerInFlight.insert(sessionID)
        defer { answerInFlight.remove(sessionID) }
        let session = store.sessions.first { $0.id == sessionID }
        // Ambiguity guard (#81): the AX enumeration cannot see hidden tabs or
        // other-Space windows at the same cwd (capture in
        // docs/spikes/81-…-ghostty.md), but the store *knows* how many live
        // Sessions share this project — two terminals at one cwd means the
        // visible tab could be either, so nothing is injected.
        let cwdIsAmbiguous = session.map { target in
            store.sessions.filter { $0.cwd == target.cwd }.count > 1
        } ?? true
        var injected = false
        if session?.state == .waiting, !cwdIsAmbiguous, let injectAnswer {
            injected = await injectAnswer(session?.cwd, optionIndex)
        }
        if injected {
            log("answer: option \(optionIndex + 1) injected → \(sessionID) « en cours »")
            store.resumeAfterAnswer(sessionID: sessionID)
        } else {
            log("answer: option \(optionIndex + 1) non injectée → dégrade en focus")
            cardActivated(sessionID: sessionID)
        }
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
    /// time — rest or waiting — and over a full-screen app: the vendored panel is
    /// `.screenSaver` + `.canJoinAllSpaces` + `.fullScreenAuxiliary`, the last of
    /// which is what actually lets it join a full-screen Space (issue #103 — the
    /// level and `.canJoinAllSpaces` alone do not). Never acknowledges: looking ≠
    /// treating (ADR-0007).
    public func reveal() {
        expandToExtended(trigger: "révélation")
    }

    /// Every global mouse move lands here (#130): the `NSEvent` monitor stays a
    /// thin shell forwarding position/screen, and this instance method holds the
    /// press state — the geometry itself stays delegated to the pure
    /// ``shouldReveal(at:in:sessionCount:)`` / ``shouldRecede(at:in:)``.
    /// A press inside the band arms the dwell; leaving the band before term
    /// re-arms it (a quick pass deploys nothing).
    public func mouseMoved(
        at location: CGPoint,
        in screenFrame: CGRect,
        sessionCount: Int
    ) {
        lastMouseSample = (location, screenFrame)
        if location.y < screenFrame.maxY - Self.edgeTolerance {
            // Off the top edge: this is the leave that re-arms the Révélation
            // after a fold — coming back to press is a new intention (#130).
            revealArmed = true
        }
        if Self.shouldReveal(at: location, in: screenFrame, sessionCount: sessionCount) {
            if mode == .expanded {
                // Re-entering the band while the Étendu is up cancels a pending
                // anti-flicker grace (the pre-#130 reveal() path, unchanged).
                reveal()
            } else {
                pressToReveal()
            }
        } else {
            // Left the band before the dwell elapsed: the quick pass reveals
            // nothing and the next press starts a fresh dwell.
            dwellTask?.cancel()
            dwellTask = nil
            if Self.shouldRecede(
                at: location, in: screenFrame,
                keepAliveDepth: recedeKeepAliveDepth
            ) {
                recedeIfClearOfPanel()
            }
        }
    }

    /// The cursor is pressed in the reveal band while the Island is not
    /// deployed: start (or keep) the dwell, and deploy when the press outlives
    /// it (#130). At most one dwell runs — repeated moves inside the band while
    /// it counts down keep the same press.
    private func pressToReveal() {
        // Post-fold guard (#130): no re-Révélation while the cooldown runs or
        // until the cursor has left the top edge since the last fold.
        guard revealArmed, !recedeCooldownActive else { return }
        guard dwellTask == nil else { return }
        dwellTask = Task { [weak self, dwellDuration] in
            try? await Task.sleep(for: dwellDuration)
            guard let self, !Task.isCancelled else { return }
            self.dwellTask = nil
            self.reveal()
        }
    }

    /// Test seam (#130): awaits the in-flight press dwell to its real
    /// completion, so the reveal tests assert the deploy (or its absence) on the
    /// task's actual settle instead of racing a fixed sleep. No-op when no press
    /// is dwelling.
    func settleDwell() async {
        await dwellTask?.value
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

    /// Test seam (issue #109): awaits the in-flight anti-flicker recede task to
    /// its real completion, so the recede tests assert the fold on the task's
    /// actual settle instead of racing a fixed sleep against the grace. No-op
    /// (returns immediately) when no recede is pending — the recede task is `nil`.
    func settleRecede() async {
        await recedeTask?.value
    }

    /// Test seam (#99): whether a Peek is currently surfaced, so the coalescence
    /// tests can assert the single continuous surface without reaching `mode`.
    var isPeeking: Bool { mode == .peek }

    /// Test seam (#99): the Session the current Peek announces, so a burst test
    /// can assert the Sprite/text was swapped in place to the latest one.
    var peekedSessionID: String? { viewModel.peekSessionID }

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
    /// The keep-alive depth is a **parameter** (#141), like the geometry: the
    /// panel grows in height with the cards, so the caller derives the depth
    /// from the real panel height (see ``recedeKeepAliveDepth``) — a fixed
    /// depth shorter than the panel folded it under the cursor on the low
    /// cards ("ça pompe" from ~3 Sessions). The function stays pure; it only
    /// bounds the depth to the top half of the screen, so the "clearly
    /// dropped away" recede always stays reachable whatever the caller
    /// derives (the vendored window itself never exceeds half a screen).
    public static func shouldRecede(
        at mouseLocation: CGPoint,
        in screenFrame: CGRect,
        keepAliveDepth: CGFloat
    ) -> Bool {
        let depthBelowEdge = screenFrame.maxY - mouseLocation.y
        let boundedKeepAliveDepth = min(keepAliveDepth, screenFrame.height / 2)
        let droppedBelowKeepAlive = depthBelowEdge > boundedKeepAliveDepth
        let outsideRecedeBand = abs(mouseLocation.x - screenFrame.midX) > recedeBandWidth / 2
        return droppedBelowKeepAlive || outsideRecedeBand
    }

    /// The view's displayed panel height landed (#141): the vertical twin of
    /// the #130 width derivation, fed by the `GeometryReader` measurement the
    /// Étendu already takes (via the view-model callback channel). Internal so
    /// the recede tests can drive the measurement directly — the rendering
    /// itself is verified visually.
    func panelHeightDidChange(_ height: CGFloat) {
        guard height != measuredPanelHeight else { return }
        measuredPanelHeight = height
        log("étendu: hauteur panneau \(Int(height)) → bande de maintien \(Int(recedeKeepAliveDepth))")
    }

    /// How far below the top edge the cursor may sit and still keep the Étendu
    /// alive (issue #60, derived in #141): covers the deployed panel's **real**
    /// height — the displayed content the view measured plus the vendored
    /// floating padding above and below (`NotchlessView` `.padding(20)`) — plus
    /// the guaranteed hysteresis margin (#130 pattern), so loitering over the
    /// low cards of a tall panel never folds it under the cursor. Never below
    /// the pre-#141 fixed depth: the first deployment (no measurement yet) and
    /// a short panel keep the previous behaviour.
    var recedeKeepAliveDepth: CGFloat {
        guard let measuredPanelHeight else { return Self.fallbackRecedeKeepAliveDepth }
        return max(
            Self.fallbackRecedeKeepAliveDepth,
            measuredPanelHeight + 2 * Self.floatingStylePadding + Self.recedeHysteresisMargin
        )
    }

    /// Native DynamicNotchKit hover, live only while a panel exists (`state !=
    /// .hidden`). Hovering a Peek promotes it to the Étendu; hovering the
    /// revealed panel keeps it open; leaving it recedes to Masqué after a grace
    /// delay. Never acknowledges (ADR-0007).
    func hoverDidChange(_ hovering: Bool) {
        if hovering {
            expandToExtended(trigger: "révélation (survol)")
        } else if mode == .expanded {
            // Spurious hover-off veto (#130): the deploy animation can flip the
            // native hover true→false while the cursor stays pinned at the top
            // edge inside the keep-alive band (the panel slides under it) — and
            // a pinned cursor fires no further mouse event to cancel a pending
            // grace, so arming here would fold the panel under the press and
            // the cooldown would then kill it. Skip the arming; the geometric
            // path folds the Étendu when the cursor actually leaves.
            if let sample = lastMouseSample,
                sample.location.y >= sample.screenFrame.maxY - Self.edgeTolerance,
                !Self.shouldRecede(
                    at: sample.location, in: sample.screenFrame,
                    keepAliveDepth: recedeKeepAliveDepth
                ) {
                return
            }
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
            self.peekMarking = nil
            self.viewModel.showCards = false
            self.beginRevealCooldown()
            self.log("masqué (curseur quitte le panneau)")
            await self.notch?.hide()
        }
    }

    /// Disarms the Révélation right after the Étendu folded (#130) — both fold
    /// paths (geometric and hover-off) funnel through ``scheduleRecede()``, so
    /// this is the single hook. Re-arming needs BOTH the cooldown to elapse and
    /// the cursor to leave the top edge (see ``mouseMoved(at:in:sessionCount:)``);
    /// the Peek's own fold never comes through here (its recede is `peekTask`),
    /// so dwell/cooldown stay out of the `peek()` path (#99).
    private func beginRevealCooldown() {
        revealArmed = false
        recedeCooldownActive = true
        cooldownTask?.cancel()
        cooldownTask = Task { [weak self, recedeCooldown] in
            try? await Task.sleep(for: recedeCooldown)
            guard let self, !Task.isCancelled else { return }
            self.recedeCooldownActive = false
        }
    }

    /// Test seam (#130): awaits the in-flight post-fold cooldown to its real
    /// expiry, so the recede tests assert the re-arm (or its absence) on the
    /// task's actual settle instead of racing a fixed sleep. No-op when no
    /// cooldown is running.
    func settleRecedeCooldown() async {
        await cooldownTask?.value
    }

    // MARK: - Peek

    /// Surfaces the Island in a transient Peek, then recedes to Masqué. Never
    /// fights the Étendu: while revealed, no Peek (ADR-0007, issue #53).
    ///
    /// Coalescence (#99): a marking event that arrives while a Peek is already
    /// out never tears the panel down to redeploy it (the "ça pompe"
    /// monte/descend, and the cross-fade of a re-Peek landing on a fade-out). It
    /// swaps the Sprite and text in place when the marking changed — a different
    /// Session or a different state — and leaves them untouched on a redundant
    /// re-announcement (an ADR-0008 gate flip, a statusline re-emit). Either way
    /// it re-arms the recede, so a whole burst is ONE continuous surface that
    /// folds back to Masqué a Peek's duration after the *last* event. Only a Peek
    /// surfaced from Masqué opens a window (and bumps `peekSurfaceCount`), so the
    /// recede's `hide()` never races a re-Peek's `expand()`.
    private func peek(for session: Session) {
        guard mode != .expanded else { return }
        let marking = (id: session.id, state: session.state)

        if mode == .peek {
            // Already surfaced: coalesce into the single live window. Only touch
            // the content when the marking actually changed, so an identical
            // re-announcement causes no view churn — but always re-arm so the
            // burst stays one continuous surface.
            if peekMarking?.id != marking.id || peekMarking?.state != marking.state {
                applyPeekContent(for: session)
                peekMarking = marking
                log("peek (coalescé): \(viewModel.peekText)")
            }
            armPeekRecede()
            return
        }

        // From Masqué: surface exactly one window.
        applyPeekContent(for: session)
        peekMarking = marking
        mode = .peek
        peekSurfaceCount += 1
        recedeTask?.cancel()
        Task { [weak self] in await self?.notch?.expand() }
        log("peek: \(viewModel.peekText)")
        armPeekRecede()
    }

    /// Sets the Peek's Sprite, announcement text and target Session, and makes
    /// the panel show the Peek (not the cards) whatever the last Reveal left.
    private func applyPeekContent(for session: Session) {
        viewModel.peekText = Self.peekText(for: session)
        viewModel.peekAnimation = Self.peekAnimation(for: session)
        viewModel.peekSessionID = session.id
        viewModel.showCards = false
    }

    /// (Re)arms the recede timer of the live Peek (#99): the single window folds
    /// back to Masqué a Peek's duration after the last marking event, unless a
    /// Reveal or a fresh coalesced event supersedes it first. `hide()` is reached
    /// only here — never while another event is still arriving — so it never
    /// races a re-Peek's `expand()` (the leaked-continuation / cross-fade path).
    private func armPeekRecede() {
        peekTask?.cancel()
        peekTask = Task { [weak self, peekDuration] in
            try? await Task.sleep(for: peekDuration)
            guard let self, !Task.isCancelled, self.mode == .peek else { return }
            self.mode = .hidden
            self.peekMarking = nil
            await self.notch?.hide()
            self.log("masqué (peek terminé)")
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
                // Live background tasks (#48, widened by #79), read from the
                // Stop's background_tasks: a Session with one is never
                // terminée. Surfaced on stdout so the agentic FP can assert the
                // count was parsed (state=running + ×Nbg proves the gate
                // engaged), the production trace of the decoded count —
                // distinct from any capture instrumentation.
                if session.activeBackgroundTaskCount > 0 {
                    parts += " ×\(session.activeBackgroundTaskCount)bg"
                }
                if session.lastSummary != nil {
                    parts += "+summary"
                }
                // Pending AskUserQuestion (issue #26): the option count lets the
                // FP assert extraction + ordering state-first (buttons stay
                // visual). Only while waiting — matches what the card renders.
                if session.state == .waiting, let question = session.pendingQuestion {
                    parts += "+question(\(question.options.count))"
                }
                // Buttonless wait that surfaced its ask (issue #29): the escalated
                // permission (or unextractable question) shows a message, not
                // buttons. The marker lets the FP assert the surfacing state-first.
                if session.state == .waiting, session.pendingQuestion == nil,
                    session.waitingMessage != nil {
                    parts += "+msg"
                }
                return parts
            }
            .joined(separator: " ")
    }

    /// What the Peek announces for a marking event on a Session: the waiting
    /// call to action, or the first line of the turn summary (ADR-0002, falls
    /// back to the bare "done" when the transcript had nothing usable).
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
    /// Answer-by-injection (issue #27): set by the controller, called with a
    /// Session id and the tapped option index when an option button is pressed.
    var answerOption: ((String, Int) -> Void)?
    /// Panel-height channel (#141): set by the controller, called by the
    /// Étendu with its **displayed** content height (measured, already capped)
    /// whenever the layout lands or changes, so the geometric recede can cover
    /// the real panel.
    var panelHeightChanged: ((CGFloat) -> Void)?
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

    /// A top-to-bottom block of the Extended panel. The Quotas gauges lead, then
    /// either the Session cards or the empty placeholder.
    enum PanelSection: Hashable {
        case quotas
        case emptyPlaceholder
        case cards
    }

    /// The panel's vertical sections, top to bottom (#69). Quotas lead so the
    /// gauges are the first thing visible when the panel opens — above the cards,
    /// not at the foot as before. The cards, or the "no sessions" placeholder
    /// when there are none, follow. Pure like `cappedHeight`, so the order is
    /// pinned by a unit test while the rendering is verified visually.
    static func sections(hasQuotas: Bool, hasCards: Bool) -> [PanelSection] {
        var sections: [PanelSection] = []
        if hasQuotas { sections.append(.quotas) }
        sections.append(hasCards ? .cards : .emptyPlaceholder)
        return sections
    }

    /// A fresh measurement landed: track it for the height cap, and report the
    /// **displayed** height — the measurement clamped by ``cappedHeight`` to
    /// what the panel actually renders — to the controller (#141), so the
    /// geometric recede's keep-alive depth covers the real panel, not a fixed
    /// constant shorter than it. Zero (pre-first-layout) reports nothing: the
    /// controller keeps its conservative fallback.
    private func measured(_ height: CGFloat) {
        contentHeight = height
        guard height > 0 else { return }
        model.panelHeightChanged?(
            Self.cappedHeight(contentHeight: height, screenHeight: screenHeight)
        )
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(
                    Self.sections(hasQuotas: !model.quotaGauges.isEmpty, hasCards: !model.cards.isEmpty),
                    id: \.self
                ) { section in
                    switch section {
                    // Quotas (issue #9): global gauges in the lead so they are
                    // the first thing seen on opening (#69), only when the
                    // statusline reported rate limits. They scroll with the list.
                    case .quotas:
                        QuotaGaugesView(gauges: model.quotaGauges)
                    case .emptyPlaceholder:
                        Text("no sessions")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .cards:
                        ForEach(model.cards) { card in
                            // Click-to-focus (issue #10): tapping the card degrades
                            // to focus. Tapping an AskUserQuestion option button
                            // (issue #27) instead attempts a safe-targeted keystroke
                            // injection, degrading to focus only when uncertain.
                            SessionCardView(
                                card: card,
                                onActivate: { model.activateSession?(card.id) },
                                onAnswer: { index in model.answerOption?(card.id, index) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.activateSession?(card.id)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: IslandController.extendedContentMaxWidth)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measured(proxy.size.height) }
                        .onChange(of: proxy.size.height) { _, newValue in
                            measured(newValue)
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
    /// Click-to-focus (issue #10): tapping the card degrades to focus.
    let onActivate: () -> Void
    /// Answer-by-injection (issue #27): tapping option N attempts a safe-targeted
    /// injection of that option, degrading to focus only when the target is
    /// uncertain — the controller decides, the view only reports the tap.
    let onAnswer: (Int) -> Void

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
                Text("\"\(prompt)\"")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let tool = card.currentTool {
                Text("tool: \(tool)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            // Discreet background-task tally (issue #48/#79, Q6): "⋯ N background
            // tasks running" — shown only while at least one runs.
            if let backgroundTasks = card.backgroundTasksLabel {
                Text("⋯ \(backgroundTasks)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // When a structured question is present (#26), IT is the card's
            // presentation: the finished-turn prose would be redundant, so the
            // summary block cedes to the question below. Exclusive by
            // construction — never rely on lastSummary happening to be nil on
            // the AskUserQuestion path (a future waiting source could break it).
            if card.question == nil, let summary = card.summaryText {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Same exclusivity as the summary text above: the turn facts belong
            // to a finished turn, not to a card blocked on a structured question
            // (#26), so they cede to the question too — and `summaryFacts` can be
            // non-nil even when `summaryText` is nil (facts without prose), so the
            // guard is on the question, not on the text being present.
            if card.question == nil, let facts = card.summaryFacts {
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
            // Buttonless wait (issue #29): an escalated permission prompt (or an
            // unextractable question, US10) carries no options to inject, so the
            // card shows the block's ask — WHAT is waiting — instead of buttons.
            // Display only: the tap degrades to Click-to-focus like any card, and
            // nothing is ever injected or auto-selected (US7). Mutually exclusive
            // with the question block below (set only when card.question is nil).
            if let waitingMessage = card.waitingMessage {
                Text(waitingMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            // AskUserQuestion (issue #26): the question label + one button per
            // option, in transcript order (the number is the 1/2/3 key mapping).
            // Tapping a button attempts a safe-targeted injection of that option
            // (issue #27); merely showing the buttons never clears the Liseré.
            if let question = card.question {
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.prompt)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                                .frame(minWidth: 12, alignment: .center)
                            Text(option.label)
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.12))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onAnswer(index) }
                    }
                }
                .padding(.top, 2)
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
