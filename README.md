<div align="center">

# island

**Your Claude Code sessions, Dynamic Island-style.**

<!-- ASSET SLOT (#101, unblock after the inaugural Release #93): badges.
     The release badge 404s until a Release is published; the license badge
     needs a LICENSE file committed first; the macOS badge is static and safe
     to uncomment any time. Once the first Release exists:
[![Latest release](https://img.shields.io/github/v/release/Taklin1/island)](https://github.com/Taklin1/island/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
[![License](https://img.shields.io/github/license/Taklin1/island)](LICENSE)
-->

<!-- ASSET SLOT (#101, capture on a published Release build, after #93):
     hero screenshot of the Island panel open over a desktop, light + dark
     themes. Files: docs/assets/hero-light.png, docs/assets/hero-dark.png.
     Uncomment once the files exist:
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/hero-dark.png">
  <img src="docs/assets/hero-light.png" alt="The island panel showing Claude Code sessions" width="720">
</picture>
-->

</div>

A native macOS app (Swift/SwiftUI) that keeps an eye on your Claude Code sessions so you don't have to:

- **Know the instant an agent needs you**: finished, or waiting on a question, even while you're working in another app, full screen included.
- **See every session at a glance**: its state, its project, what the last turn actually did.
- **Watch your Claude quotas** (5-hour and 7-day windows, context usage) without leaving your flow.

The Island stays hidden while agents work. It peeks out for a couple of seconds when something notable happens, and a colored outline along the screen edges keeps the reminder alive until you've dealt with it. Push your cursor against the top edge of the screen to open the full panel at any time.

<!-- ASSET SLOT (#101, capture on a published Release build, after #93):
     demo GIF of the nominal path: a session working → turn finishes →
     peek + green edge outline → click-to-focus back to the terminal.
     File: docs/assets/demo.gif. Uncomment once the file exists:
<div align="center">
  <img src="docs/assets/demo.gif" alt="A Claude Code session finishing: peek, edge outline, click back to the terminal" width="720">
</div>
-->

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Taklin1/island/main/scripts/install.sh | sh
```

That's it: no Gatekeeper dialogs, no sudo. The script installs the latest [release](https://github.com/Taklin1/island/releases) into `~/Applications` and launches it; running it again updates in place. Terminal downloads never carry macOS's quarantine attribute, so the app opens like any locally built binary ([ADR-0010](docs/adr/0010-distribution-sans-notarisation.md), in French).

On first launch, island hooks itself into Claude Code automatically: it adds its hooks to `~/.claude/settings.json` with an additive merge (your existing hooks are preserved), after a timestamped backup. The hooks post events to the app in the background and never block or slow down Claude Code, even when the app isn't running. Reinstall or uninstall the hooks any time from the menu-bar icon.

When a new version ships, island shows a single macOS notification and a menu-bar item. Updating is always your click, never silent.

## Features

- **Session states**: each session is a card with an animated pixel-art mascot whose animation encodes the state: working, finished, waiting for you, idle. Cards are sorted by urgency (waiting first).
  <!-- ASSET SLOT (#101, after #93): docs/assets/states-light.png / states-dark.png -->
- **Summaries**: what the last turn did (last assistant message, todos, files touched). Extracted locally from the session transcript, never an extra LLM call.
  <!-- ASSET SLOT (#101, after #93): docs/assets/summary-light.png / summary-dark.png -->
- **Quotas**: usage gauges for the 5-hour and 7-day windows plus context usage, fed by the Claude Code statusline, shown at the top of the panel.
  <!-- ASSET SLOT (#101, after #93): docs/assets/quotas-light.png / quotas-dark.png -->
- **Click-to-focus**: click a session's card to jump straight back to its terminal, targeting the exact window when it can be identified with certainty (Ghostty).
  <!-- ASSET SLOT (#101, after #93): docs/assets/focus-light.png / focus-dark.png -->
- **Answer from the Island**: when Claude asks you a question, the options appear on the card; click one and the answer is typed into that session's terminal, only when the exact window is identified and visible. Optional, on by default, degrades to click-to-focus otherwise.
  <!-- ASSET SLOT (#101, after #93): docs/assets/answer-light.png / answer-dark.png -->
- **Ambient notifications**: a colored outline along the screen edges until you acknowledge it: orange when a session waits on you, green when one finished. Plus a menu-bar mascot reflecting the most pressing state across all sessions.
  <!-- ASSET SLOT (#101, after #93): docs/assets/outline-light.png / outline-dark.png -->

## Requirements

- **macOS 14+**: any Mac, any display; the Island is a floating panel that never steals focus.
- **Claude Code**: the hooks are installed automatically on first launch.
- **Accessibility permission** (optional): powers exact-window focus and Answer from the Island. Without it, everything degrades gracefully to app-level focus; island guides you to System Settings once, and never blocks.

## Learn more

Project documentation is in French:

- [`CONTEXT.md`](CONTEXT.md): the product vocabulary (single source of truth).
- [`docs/adr/`](docs/adr/): architecture decision records.
- [`CHANGELOG.md`](CHANGELOG.md): release history.
- [git-flow](.claude/skills/git-flow/SKILL.md): branching and contribution workflow.

## Development

Run from source (Swift 6+ toolchain; the Command Line Tools are enough, see the vendoring note below):

```sh
swift run Island
```

On first launch the app generates its auth token in `~/.claude/island-token` (mode 0600), starts the local server on `http://127.0.0.1:41414` (loopback only, token-authenticated; requests without a valid token get a 401), and installs its Claude Code hooks as described above (additive merge, timestamped backup, idempotent: relaunching never duplicates entries, and an unreadable settings file is never touched). The installed hook command captures the payload in the foreground and posts it with `curl --max-time 2` in the background, failing silently, so Claude Code is never blocked. For an optimized build: `swift build -c release`, then `.build/release/Island`.

A dev build (version suffixed `-dev`) never offers or applies updates: it would overwrite itself with the released app.

Run the tests:

```sh
swift test
```

Tests follow the project's seams: JSON hook fixtures are POSTed to the local server and the published session state is asserted, never the internal implementation. SwiftUI rendering is verified visually.

**Vendoring**: [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) 1.1.0 (MIT, ADR-0003) is vendored in `Vendor/` with a micro-patch: SwiftUI macros (`@Entry`, `#Preview`) don't compile with the Command Line Tools alone (macro plugins require Xcode). The patch replaces `@Entry` with explicit `EnvironmentKey`s and removes the `#Preview`s; behavior identical to upstream. With a full Xcode installed, the URL dependency in `Package.swift` can be restored.
