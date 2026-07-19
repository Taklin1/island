import AppKit
import IslandStore

/// Click-to-focus (issue #10): brings the terminal hosting a Session to the
/// foreground. v1 activates the whole app — targeting the exact window/tab is
/// out of scope (v1.5). Activation goes through NSWorkspace, so the Island
/// (a non-activating panel in an accessory app) never becomes active itself.
@MainActor
public struct TerminalFocuser {
    /// Activates the app with this bundle identifier; false when impossible
    /// (not installed, not found).
    private let activateBundleID: (String) -> Bool
    /// Fallback: launches (or activates) an app by display name.
    private let launchApplication: (String) -> Void

    /// Seams are injectable for tests; production uses `.live`.
    public init(
        activateBundleID: @escaping (String) -> Bool,
        launchApplication: @escaping (String) -> Void
    ) {
        self.activateBundleID = activateBundleID
        self.launchApplication = launchApplication
    }

    /// Production focuser, backed by NSWorkspace.
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
        }
    )

    /// Brings the given terminal frontmost (default terminal when unknown).
    public func focus(terminal: String?) {
        let terminal = terminal ?? TerminalRegistry.defaultTerminal
        if let bundleID = TerminalRegistry.bundleID(for: terminal),
           activateBundleID(bundleID) {
            return
        }
        launchApplication(TerminalRegistry.appName(for: terminal))
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
