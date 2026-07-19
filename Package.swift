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
        // Floating Island UI (DynamicNotchKit): compact bar + peek on events.
        .target(name: "IslandUI", dependencies: ["IslandStore", "DynamicNotchKit"]),
        // App executable wiring server + adapter + store + UI.
        .executableTarget(
            name: "Island",
            dependencies: ["IslandStore", "ClaudeCodeAdapter", "IslandServer", "IslandUI"]
        ),
        .testTarget(name: "IslandStoreTests", dependencies: ["IslandStore"]),
        .testTarget(name: "ClaudeCodeAdapterTests", dependencies: ["ClaudeCodeAdapter"]),
        .testTarget(
            name: "IslandServerTests",
            dependencies: ["IslandServer", "ClaudeCodeAdapter", "IslandStore"]
        ),
    ]
)
