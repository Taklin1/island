import AppKit
import ApplicationServices
import IslandStore

/// Click-to-focus (issues #10, #36): brings the terminal hosting a Session to
/// the foreground — the Session's **exact Ghostty window** when it is a certain
/// target (the same unicity verdict as the injection, without its extra
/// guards: no keystroke is at stake, a wrong window is benign), otherwise the
/// whole app as before. Activation goes through NSWorkspace, so the Island
/// (a non-activating panel in an accessory app) never becomes active itself.
@MainActor
public struct TerminalFocuser {
    /// Activates the app with this bundle identifier; false when impossible
    /// (not installed, not found).
    private let activateBundleID: (String) -> Bool
    /// Fallback: launches (or activates) an app by display name.
    private let launchApplication: (String) -> Void
    /// Whether the process holds Accessibility trust; without it Ghostty's
    /// windows are unreadable, so the focus stays app-level — immediate, never
    /// blocking (issue #36).
    private let isTrusted: () -> Bool
    /// Enumerates the open Ghostty windows — the one window/tab mechanism
    /// shared with the injection (``GhosttyWindows``, issue #36).
    private let listWindows: () -> [TerminalWindow]

    /// Seams are injectable for tests; production uses `.live`.
    public init(
        activateBundleID: @escaping (String) -> Bool,
        launchApplication: @escaping (String) -> Void,
        isTrusted: @escaping () -> Bool,
        listWindows: @escaping () -> [TerminalWindow]
    ) {
        self.activateBundleID = activateBundleID
        self.launchApplication = launchApplication
        self.isTrusted = isTrusted
        self.listWindows = listWindows
    }

    /// Production focuser, backed by NSWorkspace and the Accessibility API.
    public static let live = TerminalFocuser(
        activateBundleID: { bundleID in
            if let running = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first {
                return running.activate()
            }
            guard let url = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: bundleID) else {
                return false
            }
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration()
            )
            return true
        },
        launchApplication: { name in
            let url = URL(fileURLWithPath: "/Applications/\(name).app")
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration()
            )
        },
        isTrusted: { AXIsProcessTrusted() },
        listWindows: GhosttyWindows.live
    )

    /// How a focus landed (issue #36): the Session's exact window, or the
    /// whole app as before. Returned so the caller can trace it — the agentic
    /// FP observes the path through stdout, never through pixels.
    public enum FocusOutcome: Equatable {
        case exactWindow
        case app
    }

    /// Brings the given terminal frontmost (default terminal when unknown):
    /// the Session's exact window when certain, the app otherwise (#36).
    @discardableResult
    public func focus(terminal: String?, cwd: String? = nil) -> FocusOutcome {
        let terminal = terminal ?? TerminalRegistry.defaultTerminal
        if let window = certainWindow(terminal: terminal, cwd: cwd) {
            window.raiseAndActivate()
            return .exactWindow
        }
        if let bundleID = TerminalRegistry.bundleID(for: terminal),
           activateBundleID(bundleID) {
            return .app
        }
        launchApplication(TerminalRegistry.appName(for: terminal))
        return .app
    }

    /// The Session's exact Ghostty window, iff it is a certain target: the
    /// unicity verdict **alone** decides (issue #36 — exactly one window whose
    /// `AXDocument` is the Session's cwd). Ghostty-only: other terminals never
    /// expose a readable cwd (spike #25). Windows are not even enumerated
    /// without Accessibility trust.
    private func certainWindow(terminal: String, cwd: String?) -> TerminalWindow? {
        guard let cwd, isTrusted(),
              TerminalRegistry.bundleID(for: terminal) == GhosttyWindows.bundleID
        else { return nil }
        let windows = listWindows()
        guard case let .certain(index) = GhosttyWindowTargeting.verdict(
            forSessionCWD: cwd, amongst: windows.map(\.cwd))
        else { return nil }
        return windows[index]
    }
}

/// Acknowledgement by terminal focus (issue #8): observing the frontmost app
/// (never polling), acknowledges the Sessions hosted by a terminal as soon as
/// the user focuses it.
@MainActor
public final class TerminalFocusAcknowledger {
    private let store: SessionStore
    // Touched from deinit (nonisolated): NotificationCenter observer removal
    // is thread-safe.
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    public init(store: SessionStore) {
        self.store = store
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Starts observing app activations system-wide.
    public func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                self?.handleActivation(bundleID: bundleID)
            }
        }
    }

    /// Acknowledges the Sessions hosted by the terminal matching this bundle
    /// identifier, if any. Exposed for tests.
    public func handleActivation(bundleID: String?) {
        guard let bundleID,
              let terminal = TerminalRegistry.terminal(forBundleID: bundleID) else {
            return
        }
        store.acknowledge(terminal: terminal)
    }
}
