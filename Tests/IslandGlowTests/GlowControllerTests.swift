import AppKit
import Testing
import IslandGlow
import IslandStore

@MainActor
struct GlowControllerTests {
    private func event(_ id: String, _ kind: AgentEventKind) -> AgentEvent {
        AgentEvent(sessionID: id, kind: kind, terminal: "ghostty", agent: "claude-code")
    }

    @Test("Waiting lights orange, Stop lights green, Acknowledgement turns it off")
    func storeDrivesTheGlow() {
        let store = SessionStore()
        let controller = GlowController(store: store, isEnabled: { true })
        controller.activate()
        defer { controller.deactivate() }

        #expect(controller.currentColor == nil)

        store.apply(event("s1", .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0)))
        #expect(controller.currentColor == .green)

        // Orange (waiting) wins over green (finished).
        store.apply(event("s2", .waitingForUser(message: "May I run Bash?")))
        #expect(controller.currentColor == .orange)

        store.acknowledge(sessionID: "s2")
        #expect(controller.currentColor == .green)

        store.acknowledgeAll()
        #expect(controller.currentColor == nil)
    }

    @Test("Liseré preference off: the glow never shows")
    func disabledPreferenceKeepsGlowOff() {
        let store = SessionStore()
        let controller = GlowController(store: store, isEnabled: { false })
        controller.activate()
        defer { controller.deactivate() }

        store.apply(event("s1", .waitingForUser(message: nil)))

        #expect(controller.currentColor == nil)
    }

    @Test("One Liseré window per screen while lit, none once acknowledged")
    func windowsFollowTheGlow() {
        let store = SessionStore()
        let controller = GlowController(store: store, isEnabled: { true })
        controller.activate()
        defer { controller.deactivate() }

        store.apply(event("s1", .waitingForUser(message: nil)))
        #expect(controller.visibleWindowCount == NSScreen.screens.count)

        store.acknowledgeAll()
        #expect(controller.visibleWindowCount == 0)
    }
}
