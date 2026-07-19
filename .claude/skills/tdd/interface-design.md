# Interface Design for Testability

Good interfaces make testing natural:

1. **Accept dependencies, don't create them**

   ```swift
   // Testable
   func handle(_ event: HookEvent, clock: Clock) { }

   // Hard to test
   func handle(_ event: HookEvent) {
       let now = Date()  // wall clock baked in
   }
   ```

2. **Return results, don't produce side effects**

   ```swift
   // Testable
   func reduce(_ state: SessionState, _ event: HookEvent) -> SessionState { }

   // Hard to test
   func apply(_ event: HookEvent) {
       self.sessionState.mutateInPlace(event)
   }
   ```

3. **Small surface area**
   - Fewer methods = fewer tests needed
   - Fewer params = simpler test setup
