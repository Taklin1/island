import AppKit
import UserNotifications
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
    /// Réponse depuis l'Island (issue #28): the Accessibility permission the
    /// injection of #27 needs, and the non-blocking onboarding to it. The gate
    /// `AnswerFromIslandGate` (IslandStore) turns the preference + this
    /// permission into inject-or-degrade; #27 consults it at the option tap.
    private let accessibility = AccessibilityPermission.live
    private let onboarding = AccessibilityOnboarding.live
    /// Re-reads Session titles on Extended open (issue #32): remembers each
    /// Session's transcript path from the hooks and re-reads it on hover, so a
    /// `/rename` on an idle/ended Session (no hook fires) still shows up.
    private let titleRefresher = ClaudeCodeTitleRefresher()
    private var server: LocalServer?
    private var controller: IslandController?
    private var glow: GlowController?
    private var focusAcknowledger: TerminalFocusAcknowledger?
    private var statusItem: NSStatusItem?
    /// Global mouse monitor for the top-edge Reveal gesture (issue #53). A thin
    /// shell: it reads the cursor and screen and delegates the decision to the
    /// pure `IslandController.shouldReveal(at:in:sessionCount:)`.
    private var revealMonitor: Any?
    /// Drives the menu-bar mascot animation (issue #54): each tick re-reads the
    /// aggregated Session state and redraws the current sprite frame.
    private var iconTimer: Timer?
    /// Last mascot animation traced to stdout, so agentic tests can assert the
    /// aggregated state without inspecting the menu-bar pixels; only prints on
    /// a change.
    private var lastMascotTrace: String?
    /// The bot sprite sheet, decoded once for the menu bar.
    private lazy var botSheet: CGImage? = SpriteSheet.bot.image(named: "bot")
    /// Mise à jour (issue #91, ADR-0010): the ref to the version menu item of
    /// #88 — the menu is built once and never rebuilt, so the title mutates in
    /// place ("island vX.Y.Z — à jour" ↔ "⬆ Mettre à jour vers vY.Z…").
    private var versionMenuItem: NSMenuItem?
    /// Daily update check (issue #91); the launch check covers a Mac waking
    /// from sleep or relaunching, no calendar scheduler needed.
    private var updateTimer: Timer?
    /// Fetches the latest release tag. Live = GitHub `releases/latest` (public
    /// API, no auth); the agentic FP swaps the URL via `ISLAND_UPDATE_FEED_URL`
    /// to serve a fixture (traced when active, see `makeUpdateFetcher`).
    private lazy var updateFetcher: UpdateFetcher = Self.makeUpdateFetcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = store
        let quotaStore = quotaStore
        let titleRefresher = titleRefresher
        // Réponse depuis l'Island (issue #28): bound as locals (like `store`
        // above) so the injectAnswer closure never captures `self` — these are
        // value-type structs, so the copy is cheap and shares the same
        // UserDefaults.
        let settings = settings
        let accessibility = accessibility
        let onboarding = onboarding
        // Version embarquée (issue #88): trace which build runs (X.Y.Z-dev for
        // local packaging, bare X.Y.Z for releases, 0.0.0-dev for the bare
        // SwiftPM binary) so the FP and "which version am I running" (US5)
        // can read it at launch.
        print("island: version \(AppVersion.current.value)")
        installHooksOnFirstLaunch()
        installMenuBarIcon()
        startUpdateChecks()
        // Réponse depuis l'Island (issue #28): trace the Accessibility
        // permission at launch so the onboarding FP can observe the branch. The
        // value can be stale until the app is relaunched after a grant (spike
        // #25), which is exactly why the trace matters across relaunches.
        print("island: accessibility permission \(accessibility.isGranted ? "granted" : "absent")")
        Task { @MainActor in
            do {
                let token = try TokenStore.loadOrCreate()
                let server = LocalServer(
                    token: token,
                    translate: { data in
                        // Remember the transcript path (issue #32) before
                        // translating, so hover can re-read the title later.
                        titleRefresher.observe(hookPayload: data)
                        return ClaudeCodeAdapter.event(fromHookPayload: data)
                    },
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
                    focusTerminal: { TerminalFocuser.live.focus(terminal: $0) },
                    // Extended open (issue #32): re-read each Session's title so
                    // a /rename that fired no hook is reflected on hover.
                    refreshTitles: {
                        for session in store.sessions {
                            if let title = titleRefresher.currentTitle(forSessionID: session.id) {
                                store.setTitle(title, forSessionID: session.id)
                            }
                        }
                    },
                    // Answer-by-injection (issue #27) gated by the preference +
                    // Accessibility permission (issue #28, US8/US9). The pure
                    // `AnswerFromIslandGate` decides: only when the feature is on
                    // *and* the permission is granted do we attempt the
                    // safe-targeted keystroke (`TerminalResponder.live`, whose own
                    // unicity guard still degrades an uncertain target to focus).
                    // Otherwise we inject nothing (return false → the controller
                    // degrades to Click-to-focus) and, on the first no-permission
                    // use, guide to System Settings once — non-blocking, never
                    // forced (ADR-0009). Real AX/CGEvent is proven only by the HITL
                    // FP on the packaged app (spike #25).
                    injectAnswer: { cwd, optionIndex in
                        switch AnswerFromIslandGate.action(
                            featureEnabled: settings.answerFromIslandEnabled,
                            permissionGranted: accessibility.isGranted,
                            onboardingAlreadyPrompted: settings.answerFromIslandOnboardingPrompted
                        ) {
                        case .inject:
                            // #81: delivery is pid-routed and verified at the
                            // instant of the post; trace the precise outcome so
                            // the HITL gate can tell "guard refused" from
                            // "delivery never verified".
                            let outcome = await TerminalResponder.live.inject(
                                optionIndex: optionIndex, forSessionCWD: cwd)
                            print("island: answer delivery \(outcome) (cwd: \(cwd ?? "nil"))")
                            return outcome == .injected
                        case .displayAndFocus(let guideToSettings):
                            if guideToSettings {
                                print("island: accessibility permission absent → guiding to"
                                    + " System Settings (answer degrades to display + focus;"
                                    + " relaunch island.app after granting)")
                                onboarding.guideToSystemSettings()
                                settings.answerFromIslandOnboardingPrompted = true
                            }
                            return false
                        }
                    }
                )
                self.controller = controller
                await controller.activate()

                // Reveal + geometric recede (issues #53, #60): a global mouse
                // monitor watches the cursor and asks the pure `shouldReveal` /
                // `shouldRecede` whether to deploy or fold the Étendu — a thin
                // shell that holds no logic of its own. The recede fallback folds
                // the panel when the cursor leaves the reveal band without ever
                // hovering the panel (the native hover-off never fires there,
                // since the panel deploys around the cursor at the edge).
                // `.mouseMoved` global events are delivered on the main thread, so
                // we stay MainActor-isolated.
                self.revealMonitor = NSEvent.addGlobalMonitorForEvents(
                    matching: .mouseMoved
                ) { [weak controller] _ in
                    MainActor.assumeIsolated {
                        guard let controller, let screen = NSScreen.main else { return }
                        let location = NSEvent.mouseLocation
                        if IslandController.shouldReveal(
                            at: location,
                            in: screen.frame,
                            sessionCount: store.sessions.count
                        ) {
                            controller.reveal()
                        } else if IslandController.shouldRecede(at: location, in: screen.frame) {
                            controller.recedeIfClearOfPanel()
                        }
                    }
                }

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

    // MARK: - Mise à jour (issue #91, ADR-0010)

    /// Update check cadence: once at launch (async, like the server start)
    /// plus a daily timer. A 86 400 s timer does not catch up across sleep,
    /// but the launch check covers a woken/relaunced Mac — sufficient per the
    /// AC. Never touches any Session surface (cards/Peek/Liseré).
    private func startUpdateChecks() {
        Task { @MainActor in await self.runUpdateCheck(trigger: "launch") }
        let timer = Timer(timeInterval: 86_400, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { @MainActor in await self.runUpdateCheck(trigger: "daily") }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    /// Fetch (nil on any failure) → pure `UpdateCheckGate` verdict → apply.
    /// Offline or API down is a silent `.unknown`: a stdout trace, nothing
    /// visible.
    private func runUpdateCheck(trigger: String) async {
        let current = Self.updateCheckCurrentVersion()
        let latestTag = await updateFetcher.fetchLatestTag()
        let verdict = UpdateCheckGate.verdict(
            currentVersion: current,
            latestTag: latestTag,
            lastNotifiedVersion: settings.lastNotifiedUpdateVersion
        )
        apply(verdict, currentVersion: current, trigger: trigger)
    }

    /// Applies a verdict: one stdout trace per verdict (the agentic FP
    /// asserts these), the in-place menu title mutation, and — first sighting
    /// of a version only — the single macOS notification, after which
    /// `lastNotifiedUpdateVersion` is persisted (the write lives here, never
    /// in the pure gate).
    private func apply(_ verdict: UpdateVerdict, currentVersion: String, trigger: String) {
        switch verdict {
        case .unknown:
            // Dev build (US15), failed fetch or unparseable version: leave
            // the resting menu title of #88 untouched.
            print("island: update verdict=unknown (dev build or no comparable release, trigger=\(trigger))")
        case .upToDate:
            print("island: update verdict=up-to-date (v\(currentVersion), trigger=\(trigger))")
            setVersionMenuItem(title: "island v\(currentVersion) — à jour", updateAvailable: false)
        case .updateAvailable(let version, let notify):
            print("island: update available v\(version) (notify=\(notify), trigger=\(trigger))")
            setVersionMenuItem(title: "⬆ Mettre à jour vers v\(version)…", updateAvailable: true)
            if notify {
                postUpdateNotification(version: version)
                settings.lastNotifiedUpdateVersion = version
            }
        }
    }

    /// Mutates the version item of #88 in place (the menu is never rebuilt).
    /// With an update available the item becomes clickable — a traced no-op
    /// until #92 wires the install script to it.
    private func setVersionMenuItem(title: String, updateAvailable: Bool) {
        guard let item = versionMenuItem else { return }
        if item.title != title {
            item.title = title
            print("island: update menu item title=\"\(title)\"")
        }
        item.isEnabled = updateAvailable
        item.action = updateAvailable ? #selector(updateClicked) : nil
        item.target = updateAvailable ? self : nil
    }

    /// One macOS notification per version (ADR-0010), tolerated-with-trace
    /// like `LoginItem`: `UNUserNotificationCenter.current()` raises when the
    /// process has no bundle (the bare SwiftPM binary the agentic FP drives),
    /// so the bundle guard skips it there — the real banner is only provable
    /// on the packaged island.app; the FP asserts the traces.
    private func postUpdateNotification(version: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            print("island: update notification skipped (bare SwiftPM binary, no bundle) (v\(version))")
            return
        }
        Task {
            do {
                let center = UNUserNotificationCenter.current()
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    // Refusal never blocks the check (ADR-0010): the menu
                    // item still proposes the update.
                    print("island: update notification not authorized (v\(version))")
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "island"
                content.body = "Mise à jour disponible : v\(version). "
                    + "Ouvrez le menu island pour l'installer."
                let request = UNNotificationRequest(
                    identifier: "island-update-\(version)", content: content, trigger: nil)
                try await center.add(request)
                print("island: update notification posted (v\(version))")
            } catch {
                print("island: update notification failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func checkForUpdatesClicked() {
        print("island: update check requested from menu")
        Task { @MainActor in await self.runUpdateCheck(trigger: "menu") }
    }

    /// Clicking "⬆ Mettre à jour vers vY.Z…" stays a traced no-op; #92 wires
    /// the install script (the same one as the Canal d'installation) to it.
    @objc private func updateClicked() {
        print("island: update click (no-op, wired in #92)")
    }

    /// Agentic FP seam (issue #91): the bare SwiftPM binary is always `-dev`
    /// (US15: it never updates), so the FP overrides the two gate inputs to
    /// exercise the update-available path against a served fixture. Both
    /// overrides are traced when active and are read ONLY by the update
    /// check — the install action of #92 must consult `AppVersion.current`
    /// directly, so the dev guard on real updates cannot be bypassed here.
    private static func makeUpdateFetcher() -> UpdateFetcher {
        guard let feed = ProcessInfo.processInfo.environment["ISLAND_UPDATE_FEED_URL"] else {
            return .live
        }
        print("island: update feed override \(feed) (agentic FP seam)")
        return UpdateFetcher { await UpdateFetcher.fetchTag(fromURLString: feed) }
    }

    private static func updateCheckCurrentVersion() -> String {
        guard
            let override = ProcessInfo.processInfo.environment["ISLAND_UPDATE_CURRENT_OVERRIDE"]
        else {
            return AppVersion.current.value
        }
        print("island: update current-version override \(override) (agentic FP seam)")
        return override
    }

    // MARK: - Menu bar

    private func installMenuBarIcon() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.menu = buildMenu()
        statusItem = item
        startMenuBarAnimation()
        print("island: menu bar icon installed")
    }

    /// Icône animée (issue #54): a single pixel-art mascot in the menu bar,
    /// animating the most pressing aggregated Session state (waiting > terminé >
    /// working > idle). When the preference is off, the timer stays down and the
    /// status item shows a static neutral icon — the menu is reachable either
    /// way. Uses `.common` mode so the frames keep advancing while the menu is
    /// open.
    private func startMenuBarAnimation() {
        iconTimer?.invalidate()
        iconTimer = nil
        refreshMenuBarIcon()
        guard settings.menuBarIconEnabled else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMenuBarIcon() }
        }
        RunLoop.main.add(timer, forMode: .common)
        iconTimer = timer
    }

    /// Redraws the menu-bar mascot from the live Session state, or the static
    /// neutral icon when the mascot is disabled (or its sheet is unavailable).
    private func refreshMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        if settings.menuBarIconEnabled {
            let mascot = SpriteAnimation.menuBarMascot(for: store.sessions)
            traceMascot(mascot.rawValue)
            if let image = Self.menuBarImage(for: mascot, sheet: botSheet) {
                button.image = image
                button.title = ""
                return
            }
        } else {
            traceMascot("static")
        }
        let neutral = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "Island")
        neutral?.isTemplate = true
        button.image = neutral
        button.title = neutral == nil ? "⏺" : ""
    }

    private func traceMascot(_ value: String) {
        guard lastMascotTrace != value else { return }
        lastMascotTrace = value
        print("island: menu bar mascot=\(value)")
    }

    /// Renders the current frame of a mascot animation into a menu-bar-sized
    /// NSImage (nearest-neighbor, kept in color so the state tints show — not a
    /// template).
    private static func menuBarImage(for animation: SpriteAnimation, sheet cg: CGImage?) -> NSImage? {
        guard let cg else { return nil }
        let sheet = SpriteSheet.bot
        let index = sheet.frameIndex(for: animation, elapsed: Date().timeIntervalSinceReferenceDate)
        guard let frame = cg.cropping(to: sheet.frameRect(for: animation, frame: index)) else { return nil }
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.interpolationQuality = .none
            ctx.draw(frame, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Version embarquée (issue #88, US5): the resting menu shows which
        // build runs. Display-only — no action, and explicitly disabled since
        // autoenablesItems is off. The update check (issue #91) keeps a ref
        // and mutates this item in place ("island vX.Y.Z — à jour" ↔
        // "⬆ Mettre à jour vers vY.Z…"); the menu itself is never rebuilt.
        let version = NSMenuItem(
            title: "island v\(AppVersion.current.value)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        versionMenuItem = version

        // Mise à jour (issue #91): manual check, same path as the launch and
        // daily checks — every verdict lands as a stdout trace + the version
        // item title above.
        let checkForUpdates = NSMenuItem(
            title: "Vérifier les mises à jour…",
            action: #selector(checkForUpdatesClicked), keyEquivalent: "")
        checkForUpdates.target = self
        menu.addItem(checkForUpdates)

        menu.addItem(.separator())

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

        let mascot = NSMenuItem(
            title: "Afficher l'Icône animée",
            action: #selector(toggleMenuBarIcon(_:)), keyEquivalent: "")
        mascot.target = self
        mascot.state = settings.menuBarIconEnabled ? .on : .off
        menu.addItem(mascot)

        let tee = NSMenuItem(
            title: "Quotas via la statusline",
            action: #selector(toggleStatuslineTee(_:)), keyEquivalent: "")
        tee.target = self
        tee.state = settings.statuslineTeeEnabled ? .on : .off
        menu.addItem(tee)

        let answer = NSMenuItem(
            title: "Réponse depuis l'Island",
            action: #selector(toggleAnswerFromIsland(_:)), keyEquivalent: "")
        answer.target = self
        answer.state = settings.answerFromIslandEnabled ? .on : .off
        menu.addItem(answer)

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

    @objc private func toggleMenuBarIcon(_ sender: NSMenuItem) {
        settings.menuBarIconEnabled.toggle()
        sender.state = settings.menuBarIconEnabled ? .on : .off
        print("island: preference menuBarIconEnabled=\(settings.menuBarIconEnabled)")
        // Restart (or tear down) the animation to match the new preference.
        startMenuBarAnimation()
    }

    /// Réponse depuis l'Island (issue #28, US8/US9): flips the preference and,
    /// when enabling the feature is the first use without the Accessibility
    /// permission, guides to System Settings once — non-blocking, never forced.
    /// The feature still degrades to display + focus until the grant; the option
    /// tap (#27) consults the same `AnswerFromIslandGate` to decide inject vs
    /// degrade.
    @objc private func toggleAnswerFromIsland(_ sender: NSMenuItem) {
        settings.answerFromIslandEnabled.toggle()
        sender.state = settings.answerFromIslandEnabled ? .on : .off
        print("island: preference answerFromIslandEnabled=\(settings.answerFromIslandEnabled)")

        let action = AnswerFromIslandGate.action(
            featureEnabled: settings.answerFromIslandEnabled,
            permissionGranted: accessibility.isGranted,
            onboardingAlreadyPrompted: settings.answerFromIslandOnboardingPrompted
        )
        if case .displayAndFocus(let guideToSettings) = action, guideToSettings {
            print("island: accessibility permission absent → guiding to System Settings"
                + " (Réponse depuis l'Island degrades to display + focus until granted;"
                + " relaunch island.app after granting)")
            onboarding.guideToSystemSettings()
            settings.answerFromIslandOnboardingPrompted = true
        }
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
