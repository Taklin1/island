# Good and Bad Tests

## Good Tests

**Integration-style**: Test through real interfaces, not mocks of internal parts.

```swift
// GOOD: Tests observable behavior
@Test func agentFinishedEventMarksSessionIdle() throws {
    let store = SessionStore()
    store.ingest(hookFixture(.stop, session: "s1"))
    #expect(store.session("s1")?.status == .idle)
}
```

Characteristics:

- Tests behavior users/callers care about
- Uses the public API only
- Survives internal refactors
- Describes WHAT, not HOW
- One logical assertion per test

For island, the strongest tests drive the app the way its hooks do: feed a JSON hook fixture through the local event API, then assert on the published Session state.

## Bad Tests

**Implementation-detail tests**: Coupled to internal structure.

```swift
// BAD: Tests implementation details
@Test func ingestCallsReducerThenNotifier() throws {
    let spy = ReducerSpy()
    store.ingest(event)
    #expect(spy.reduceCallCount == 1)
}
```

Red flags:

- Mocking internal collaborators
- Testing private methods
- Asserting on call counts/order
- Test breaks when refactoring without behavior change
- Test name describes HOW not WHAT
- Verifying through external means instead of the interface

```swift
// BAD: Bypasses the interface to verify internal state
@Test func ingestSetsPrivateDictionary() throws {
    store.ingest(hookFixture(.start, session: "s1"))
    #expect(store.rawSessionsDict["s1"] != nil)  // reaches past the interface
}

// GOOD: Verifies through the interface
@Test func ingestedSessionBecomesQueryable() throws {
    store.ingest(hookFixture(.start, session: "s1"))
    #expect(store.session("s1") != nil)
}
```
