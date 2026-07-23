import AppKit
import SwiftUI
import Testing
@testable import DynamicNotchKit

/// island guard (issue #131): an `expand()` that lands while a `hide()` is
/// mid-flight cancels the hide's `closePanelTask`. Upstream 1.1.0 then exits
/// the task through a cancellation guard *without* calling the completion, so
/// `await hide()` never resumes — `SWIFT TASK CONTINUATION MISUSE: hide()
/// leaked its continuation` (observed under PR #104's instrumentation, the
/// Peek pump / cross-fade race). The vendored patch guarantees the completion
/// fires on every exit path of `closePanelTask`, so `hide()` always resumes
/// and the interrupting `expand()` keeps the panel in a coherent state.
/// This is a vendored divergence from upstream 1.1.0 — run it via
/// `swift test --package-path Vendor/DynamicNotchKit` (the root gate does not
/// build a path dependency's own test target).
/// Mutable box for the poll-based bounded wait (a `struct` test cannot hold
/// mutable state across the awaits).
@MainActor
private final class ResumeFlag {
    var value = false
}

@MainActor
@Suite(.serialized)
struct DynamicNotchHideContinuationTests {
    @Test("hide() interrupted by expand() still resumes, and the notch ends up expanded")
    func hideInterruptedByExpandResumes() async {
        let notch = DynamicNotch(style: .floating) {
            Text("island #131")
        }

        await notch.expand()
        #expect(notch.state == .expanded)

        // Start a hide, then interrupt it inside its 0.25 s close window:
        // expand() cancels the in-flight closePanelTask.
        let resumed = ResumeFlag()
        Task {
            await notch.hide()
            resumed.value = true
        }
        try? await Task.sleep(for: .milliseconds(100))
        await notch.expand()

        // The await hide() must resume within a bounded delay. Poll a flag
        // instead of awaiting the task's value: on the upstream leak, hide()
        // never resumes, and awaiting the pending task would not respond to
        // cancellation — the wait itself must stay bounded for the suite to
        // report RED instead of hanging.
        for _ in 0..<40 where !resumed.value {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(resumed.value, "await hide() leaked its continuation when expand() cancelled the in-flight close")
        #expect(notch.state == .expanded)

        // Teardown: fold the panel back down so the suite leaves no window.
        // This uninterrupted hide() also exercises the nominal close path
        // end-to-end (sleep → fadeOutWindow → deinitializeWindow) with the
        // patch in place.
        await notch.hide()
        #expect(notch.state == .hidden)
    }
}
