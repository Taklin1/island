---
name: to-issues
description: Break a plan, spec, or PRD into independently-grabbable issues on the project issue tracker using tracer-bullet vertical slices. Use when user wants to convert a plan into issues, create implementation tickets, or break down work into issues.
---

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

The issue tracker and triage label vocabulary should have been provided to you - run `/setup-matt-pocock-skills` if not.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes an issue reference (issue number, URL, or path) as an argument, fetch it from the issue tracker and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Issue titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (event ingestion, Session state, SwiftUI pill, tests)
- A completed slice is demoable or verifiable on its own (via the local event API, `swift test`, and a screenshot for anything visual)
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source material has them)

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Publish the issues to the issue tracker

For each approved slice, publish a new issue to the issue tracker. Use the issue body template below. AFK slices get the AFK-readiness triage label; HITL slices get the human-readiness one. Never label a HITL slice for agents.

Publish issues in dependency order (blockers first) so you can reference real issue identifiers in the "Blocked by" field.

<issue-template>
## Parent

A reference to the parent issue on the issue tracker (if the source was an existing issue, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

Avoid specific file paths or code snippets HERE. They go stale fast, and this section is the durable spec. Point-in-time audit evidence belongs in `## Grilling` below, which is explicitly a snapshot. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it here and note briefly that it came from a prototype. Trim to the decision-rich parts, not a working demo, just the important bits.

## Grilling

Required on every AFK slice. This is what makes the issue self-carrying for an agent holding none of this conversation's context, and it is what an epic orchestrator gates on before it launches anything.

- **Root cause**, anchored on a SYMBOL (function name, literal string, type or case name) with `file:line` as a hint, plus the commit SHA you read it at. Line numbers drift, symbols do not. Never cite a line you have not just verified against the file: check them mechanically before publishing.
- **Evidence** that proves the root cause: the query, the log line, the measurement, with its actual numbers.
- **Traps**: what a naive implementation would silently break. Write it here, or an agent finds it at merge time.
- **Files to touch**, including any twin that a parity test keeps byte-identical.
- **Size**: S / M / L.
- **Frozen decisions**: what the human already settled, and where it is recorded (ADR path + commit). Mark them FROZEN so no agent reopens them.

Omit this section only on HITL slices, which no agent will pick up.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- A reference to the blocking ticket (if any)

Or "None - can start immediately" if no blockers.

</issue-template>

### 6. Wire the slices to the parent

Publishing loose issues is not enough. An orchestrator discovers sub-issues through the tracker's **native** parent/child link, never by reading a "Parent: #N" line in prose. A parent with no linked children looks like an empty epic.

- **Link every AFK slice as a native sub-issue** of the parent. Keep HITL slices out of that link: they do not carry the AFK label and would fail an orchestrator's readiness gate.
- **Label the parent as an epic** once it has two or more slices, and remove any AFK-readiness label from it. The parent is a container, not a task an agent can pick up.
- **Append an execution order to the parent whenever any slice has a blocker.** You built the dependency graph in step 4; do not throw it away. Group the slices into waves, and give the one-line reason each dependency exists. An orchestrator that cannot see the reason will "optimise" the ordering away and launch agents onto code that does not exist yet.
- **Project board**: island has no GitHub Project board yet. Skip this step. If one is added later, document its identifiers in the per-repo agent docs and add issues to it.

The repo's tracker, label vocabulary, and the exact commands (including how to create a native sub-issue link, which the `gh` CLI does not expose as a flag — use the GraphQL `addSubIssue` mutation) live in the per-repo agent docs (`docs/agents/`). Read them; do not duplicate them here, and do not invent them.

Never close the parent, and never rewrite the body it already had. Appending an execution-order section, linking sub-issues, and adjusting the parent's labels are expected and allowed.
