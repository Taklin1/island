import AppKit
import ClaudeCodeAdapter
import IslandFocus
import IslandGlow
import IslandInstaller
import IslandServer
import IslandStore
import IslandUI

/// Island executable: wires token → local server → Claude Code adapter →
/// session store → Island UI, installs the Claude Code hooks on first launch,
/// and lives in the menu bar (preferences, hook uninstall, quit). Runs as an
/// accessory app (no Dock icon, never activated) so it can never steal focus
/// from the terminal.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    private let quotaStore = QuotaStore()
    private let settings = AppSettings()
    private var server: LocalServer?
    private var controller: IslandController?
    private var glow: GlowController?
    private var focusAcknowledger: TerminalFocusAcknowledger?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = store
        let quotaStore = quotaStore
        installHooksOnFirstLaunch()
        installMenuBarIcon()
        Task { @MainActor in
            do {
                let token = try TokenStore.loadOrCreate()
                let server = LocalServer(
                    token: token,
                    translate: ClaudeCodeAdapter.event(fromHookPayload:),
                    publish: { event in
                        // The server already answered the hook; publishing is
                        // asynchronous and never blocks Claude Code.
                        Task { @MainActor in store.apply(event) }
                    },
                    // Quotas (issue #9): the statusline tee posts here.
                    translateStatusline: QuotaUpdate.init(statuslineJSON:),
                    publishQuota: { update in
                        Task { @MainActor in quotaStore.apply(update) }
                    }
                )
                self.server = server
                let port = try await server.start()
                print("island: listening on http://127.0.0.1:\(port) (token: ~/.claude/island-token)")

                let controller = IslandController(
                    store: store,
                    quotaStore: quotaStore,
                    focusTerminal: { TerminalFocuser.live.focus(terminal: $0) }
                )
                self.controller = controller
                await controller.activate()

                // Liseré (issue #8): reads the preference live on each change.
                let glow = GlowController(
                    store: store,
                    isEnabled: { [settings] in settings.borderEnabled }
                )
                self.glow = glow
                glow.activate()

                // Acknowledgement by terminal focus (issue #8).
                let focusAcknowledger = TerminalFocusAcknowledger(store: store)
                self.focusAcknowledger = focusAcknowledger
                focusAcknowledger.start()
            } catch {
                fputs("island: failed to start local server: \(error)\n", stderr)
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Hooks lifecycle (issue #6)

    /// First launch only: merge the island hooks into ~/.claude/settings.json
    /// (additive, backed up, idempotent) and register the login item. Later
    /// launches never re-install, so uninstalling from the menu sticks.
    private func installHooksOnFirstLaunch() {
        guard !settings.hooksInstallAttempted else {
            print("island: hooks install already attempted, skipping (uninstall/reinstall from the menu)")
            return
        }
        settings.hooksInstallAttempted = true
        installHooks()
        LoginItem.setEnabled(true)
    }

    private func installHooks() {
        do {
            let installer = HookInstaller(settingsURL: HookInstaller.defaultSettingsURL)
            switch try installer.install() {
            case .installed(let backup):
                print("island: hooks installed into ~/.claude/settings.json"
                    + (backup.map { " (backup: \($0.path))" } ?? " (new file, no backup needed)"))
            case .alreadyInstalled:
                print("island: hooks already installed, nothing to do")
            }
        } catch {
            fputs("island: hooks install failed: \(error)\n", stderr)
        }
    }

    @objc private func uninstallHooks() {
        do {
            let installer = HookInstaller(settingsURL: HookInstaller.defaultSettingsURL)
            switch try installer.uninstall() {
            case .uninstalled(let backup):
                print("island: hooks uninstalled from ~/.claude/settings.json"
                    + (backup.map { " (backup: \($0.path))" } ?? ""))
            case .nothingToUninstall:
                print("island: no island hooks found, nothing to uninstall")
            }
        } catch {
            fputs("island: hooks uninstall failed: \(error)\n", stderr)
        }
    }

    @objc private func reinstallHooks() {
        installHooks()
    }

    // MARK: - Statusline tee (issue #9, opt-in)

    /// Opt-in: inserts the marked tee block into the user's statusline script
    /// (timestamped backup, idempotent). Opt-out: removes the block and
    /// restores the previous behavior. The preference only flips when the
    /// script edit actually succeeded.
    @objc private func toggleStatuslineTee(_ sender: NSMenuItem) {
        let installer = StatuslineTeeInstaller(scriptURL: StatuslineTeeInstaller.defaultScriptURL)
        do {
            if settings.statuslineTeeEnabled {
                switch try installer.uninstall() {
                case .uninstalled(let backup):
                    print("island: statusline tee removed"
                        + (backup.map { " (backup: \($0.path))" } ?? ""))
                case .nothingToUninstall:
                    print("island: no statusline tee block found, nothing to remove")
                }
                settings.statuslineTeeEnabled = false
            } else {
                switch try installer.install() {
                case .installed(let backup):
                    print("island: statusline tee installed into "
                        + StatuslineTeeInstaller.defaultScriptURL.path
                        + (backup.map { " (backup: \($0.path))" } ?? ""))
                case .alreadyInstalled:
                    print("island: statusline tee already installed, nothing to do")
                }
                settings.statuslineTeeEnabled = true
            }
        } catch {
            fputs("island: statusline tee toggle failed: \(error)\n", stderr)
        }
        sender.state = settings.statuslineTeeEnabled ? .on : .off
        print("island: preference statuslineTeeEnabled=\(settings.statuslineTeeEnabled)")
    }

    // MARK: - Menu bar

    private func installMenuBarIcon() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "water.waves",
                accessibilityDescription: "Island"
            )
            button.image?.isTemplate = true
            if button.image == nil { button.title = "⏺" }
        }
        item.menu = buildMenu()
        statusItem = item
        print("island: menu bar icon installed")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let border = NSMenuItem(
            title: "Liseré", action: #selector(toggleBorder(_:)), keyEquivalent: "")
        border.target = self
        border.state = settings.borderEnabled ? .on : .off
        menu.addItem(border)

        let sound = NSMenuItem(
            title: "Son", action: #selector(toggleSound(_:)), keyEquivalent: "")
        sound.target = self
        sound.state = settings.soundEnabled ? .on : .off
        menu.addItem(sound)

        let tee = NSMenuItem(
            title: "Quotas via la statusline",
            action: #selector(toggleStatuslineTee(_:)), keyEquivalent: "")
        tee.target = self
        tee.state = settings.statuslineTeeEnabled ? .on : .off
        menu.addItem(tee)

        menu.addItem(.separator())

        let login = NSMenuItem(
            title: "Ouvrir à la connexion", action: #selector(toggleLoginItem(_:)),
            keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let install = NSMenuItem(
            title: "Réinstaller les hooks Claude Code",
            action: #selector(reinstallHooks), keyEquivalent: "")
        install.target = self
        menu.addItem(install)

        let uninstall = NSMenuItem(
            title: "Désinstaller les hooks Claude Code",
            action: #selector(uninstallHooks), keyEquivalent: "")
        uninstall.target = self
        menu.addItem(uninstall)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quitter Island", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)

        return menu
    }

    @objc private func toggleBorder(_ sender: NSMenuItem) {
        settings.borderEnabled.toggle()
        sender.state = settings.borderEnabled ? .on : .off
        print("island: preference borderEnabled=\(settings.borderEnabled)")
        glow?.refresh()
    }

    @objc private func toggleSound(_ sender: NSMenuItem) {
        settings.soundEnabled.toggle()
        sender.state = settings.soundEnabled ? .on : .off
        print("island: preference soundEnabled=\(settings.soundEnabled)")
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        let target = !LoginItem.isEnabled
        LoginItem.setEnabled(target)
        sender.state = LoginItem.isEnabled ? .on : .off
    }
}

// Line-buffered stdout even when redirected to a file, so the lifecycle
// traces stay observable by agentic tests.
setvbuf(stdout, nil, _IOLBF, 0)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
