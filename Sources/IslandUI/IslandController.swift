import Combine
import DynamicNotchKit
import IslandStore
import SwiftUI

/// Drives the Island (ADR-0003): a compact floating bar by default, and a
/// 2-3 s Peek — "<project> ✓ terminé" — when a Session ends, then back to
/// compact. The panel is non-activating (DynamicNotchKit uses a
/// `.nonactivatingPanel`), so it never steals focus from the terminal.
///
/// Depends only on the generic session store (ADR-0004).
@MainActor
public final class IslandController {
    private let store: SessionStore
    private let viewModel = IslandViewModel()
    private var notch: DynamicNotch<PeekView, CompactLeadingView, CompactTrailingView>?
    private var cancellables: Set<AnyCancellable> = []
    private var knownEndedSessionIDs: Set<String> = []
    private var peekTask: Task<Void, Never>?

    /// How long a Peek stays on screen before folding back to compact.
    private let peekDuration: Duration = .seconds(2.5)

    public init(store: SessionStore) {
        self.store = store
    }

    /// Shows the compact Island and starts reacting to session changes.
    public func activate() async {
        let viewModel = viewModel
        // `.notch` (not `.auto`/`.floating`): in DynamicNotchKit, the floating
        // style *hides* the panel in compact state, so a notchless Mac would
        // have no visible compact Island at all. The notch style falls back to
        // a 300 pt top-center bar on notchless screens — the micro-bar we want.
        let notch = DynamicNotch(
            hoverBehavior: [],
            style: .notch,
            expanded: { PeekView(model: viewModel) },
            compactLeading: { CompactLeadingView() },
            compactTrailing: { CompactTrailingView(model: viewModel) }
        )
        self.notch = notch
        await notch.compact()

        store.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                MainActor.assumeIsolated {
                    self?.sessionsDidChange(sessions)
                }
            }
            .store(in: &cancellables)
    }

    private func sessionsDidChange(_ sessions: [Session]) {
        viewModel.compactStatus = Self.compactStatus(for: sessions)

        let newlyEnded = sessions.filter {
            $0.state == .ended && !knownEndedSessionIDs.contains($0.id)
        }
        knownEndedSessionIDs = Set(sessions.filter { $0.state == .ended }.map(\.id))

        if let session = newlyEnded.last {
            peek(for: session)
        }
    }

    /// Expands the Island for a short while, then folds back to compact.
    private func peek(for session: Session) {
        viewModel.peekText = "\(session.projectName) ✓ terminé"

        peekTask?.cancel()
        peekTask = Task { [weak self, peekDuration] in
            guard let self, let notch = self.notch else { return }
            log("peek shown: \(self.viewModel.peekText)")
            await notch.expand()
            try? await Task.sleep(for: peekDuration)
            guard !Task.isCancelled else { return }
            await notch.compact()
            log("peek folded back to compact")
        }
    }

    /// Timestamped stdout trace of the Island lifecycle, so agentic tests can
    /// assert the peek behavior state-first (the pixels are checked visually).
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("island: [\(timestamp)] \(message)")
    }

    static func compactStatus(for sessions: [Session]) -> String {
        let ended = sessions.filter { $0.state == .ended }.count
        let active = sessions.count - ended
        switch (active, ended) {
        case (0, 0): return "–"
        case (let active, 0): return "\(active)●"
        case (0, let ended): return "\(ended)✓"
        default: return "\(active)● \(ended)✓"
        }
    }
}

/// Observable UI state, kept as plain text for this tracer bullet.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published var peekText: String = ""
    @Published var compactStatus: String = "–"
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
    }
}

struct CompactLeadingView: View {
    var body: some View {
        Text("🏝")
            .font(.system(size: 12))
    }
}

struct CompactTrailingView: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        Text(model.compactStatus)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
    }
}
