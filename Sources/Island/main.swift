import AppKit
import ClaudeCodeAdapter
import IslandServer
import IslandStore
import IslandUI

/// Island executable: wires token → local server → Claude Code adapter →
/// session store → Island UI. Runs as an accessory app (no Dock icon, never
/// activated) so it can never steal focus from the terminal.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    private var server: LocalServer?
    private var controller: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = store
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
                    }
                )
                self.server = server
                let port = try await server.start()
                print("island: listening on http://127.0.0.1:\(port) (token: ~/.claude/island-token)")

                let controller = IslandController(store: store)
                self.controller = controller
                await controller.activate()
            } catch {
                fputs("island: failed to start local server: \(error)\n", stderr)
                NSApplication.shared.terminate(nil)
            }
        }
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
