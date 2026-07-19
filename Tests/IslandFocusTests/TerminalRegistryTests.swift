import Testing
import IslandFocus

struct TerminalRegistryTests {
    @Test("ghostty resolves to the Ghostty bundle identifier, both ways")
    func ghosttyResolvesToBundleID() {
        #expect(TerminalRegistry.bundleID(for: "ghostty") == "com.mitchellh.ghostty")
        #expect(TerminalRegistry.terminal(forBundleID: "com.mitchellh.ghostty") == "ghostty")
    }

    @Test("Unknown terminals and foreign apps resolve to nothing")
    func unknownTerminalResolvesToNil() {
        #expect(TerminalRegistry.bundleID(for: "warp") == nil)
        #expect(TerminalRegistry.terminal(forBundleID: "com.apple.Safari") == nil)
    }

    @Test("The default terminal is ghostty")
    func defaultTerminalIsGhostty() {
        #expect(TerminalRegistry.defaultTerminal == "ghostty")
    }
}
