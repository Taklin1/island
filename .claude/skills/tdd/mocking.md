# When to Mock

Mock at **system boundaries** only:

- External processes / CLIs the app shells out to
- Time / randomness (inject a `Clock`, seed the RNG)
- File system (sometimes)
- The network, if any is ever added

island has no database and no remote backend: most of the app is pure, in-process state (the reducer that turns hook events into published Session state). That code needs no mocks at all - test it directly through its interface.

Don't mock:

- Your own types / modules
- Internal collaborators
- Anything you control

## Designing for Mockability

At system boundaries, design interfaces that are easy to substitute:

**1. Use dependency injection**

Pass external dependencies in rather than creating them internally:

```swift
// Easy to substitute
func timestamp(now: () -> Date) -> Date {
    now()
}

// Hard to substitute
func timestamp() -> Date {
    Date()  // wall clock baked in
}
```

**2. Prefer a narrow protocol per boundary over one generic escape hatch**

Define a focused protocol for each external operation instead of a single catch-all that tests must branch inside:

```swift
// GOOD: each boundary is independently substitutable
protocol Clock { func now() -> Date }
protocol Notifier { func notifyAgentFinished(_ session: SessionID) }

// BAD: one generic sink; the test fake needs conditional logic to know what was called
protocol SideEffects { func perform(_ kind: String, _ payload: [String: Any]) }
```

The narrow-protocol approach means:
- Each fake returns one specific shape
- No conditional logic in test setup
- Easy to see which boundaries a test exercises
- Type safety per boundary

## Testing island through its real seams

The highest-value seam is the app's local event API: POST a JSON hook fixture, then assert on the published Session state. That exercises the real reducer and wiring end-to-end without mocking anything internal. The SwiftUI rendering is checked visually (screenshots), not through mocks.
