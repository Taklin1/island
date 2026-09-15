// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Island",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Vendored copy of DynamicNotchKit 1.1.0 (MIT, ADR-0003), patched so it
        // builds with Command Line Tools only (no SwiftUI macro plugins without
        // Xcode). See Vendor/DynamicNotchKit — switch back to the upstream URL
        // once a full Xcode toolchain is available.
        .package(path: "Vendor/DynamicNotchKit")
    ],
    targets: [
        // Generic event schema + session store. Per ADR-0004, this is the only
        // vocabulary the UI ever sees — no hook format beyond the adapter.
        .target(name: "IslandStore"),
        // Translates raw Claude Code hook payloads into generic AgentEvents.
        .target(name: "ClaudeCodeAdapter", dependencies: ["IslandStore"]),
        // Local HTTP server (127.0.0.1), token-authenticated entry point for events.
        .target(name: "IslandServer", dependencies: ["IslandStore"]),
        // Installs/uninstalls the Claude Code hooks in ~/.claude/settings.json
        // (additive merge, timestamped backup, idempotent — ADR-0001).
        .target(name: "IslandInstaller"),
        // Liseré (issue #8): full-screen click-through glow window, orange when
        // a Session waits, green when one finished, until Acknowledgement.
        .target(name: "IslandGlow", dependencies: ["IslandStore"]),
        // Click-to-focus (issue #10): brings the Session's terminal frontmost
        // and acknowledges on terminal focus.
        .target(name: "IslandFocus", dependencies: ["IslandStore"]),
        // Relais (issue #157, ADR-0014): pushes the Instantané to the Totem over
        // plain HTTP on the LAN — the app's only outbound path, fed by the
        // store and the QuotaStore, never by the hooks.
        .target(name: "IslandRelay", dependencies: ["IslandStore"]),
        // Floating Island UI (DynamicNotchKit): compact bar + peek on events.
        // Resources: embedded pixel-art sprite sheets (issue #11), generated
        // by scripts/generate_sprites.py.
        .target(
            name: "IslandUI",
            dependencies: ["IslandStore", "DynamicNotchKit"],
            resources: [.process("Resources")]
        ),
        // App executable wiring server + adapter + store + UI.
        .executableTarget(
            name: "Island",
            dependencies: [
                "IslandStore", "ClaudeCodeAdapter", "IslandServer", "IslandUI",
                "IslandInstaller", "IslandGlow", "IslandFocus", "IslandRelay",
            ]
        ),
        .testTarget(name: "IslandStoreTests", dependencies: ["IslandStore"]),
        .testTarget(name: "IslandGlowTests", dependencies: ["IslandGlow", "IslandStore"]),
        .testTarget(name: "IslandFocusTests", dependencies: ["IslandFocus", "IslandStore"]),
        .testTarget(name: "IslandInstallerTests", dependencies: ["IslandInstaller"]),
        // The fake Totem reuses the local server's HTTP parser (@testable).
        .testTarget(
            name: "IslandRelayTests",
            dependencies: ["IslandRelay", "IslandStore", "IslandServer"]
        ),
        // Pure presentation logic only (labels, glyphs, durations) — the
        // SwiftUI rendering itself is checked visually, never by tests.
        .testTarget(
            name: "IslandUITests",
            dependencies: ["IslandUI", "IslandStore", "DynamicNotchKit"]
        ),
        .testTarget(name: "ClaudeCodeAdapterTests", dependencies: ["ClaudeCodeAdapter"]),
        .testTarget(
            name: "IslandServerTests",
            dependencies: ["IslandServer", "ClaudeCodeAdapter", "IslandStore"]
        ),
    ]
)
