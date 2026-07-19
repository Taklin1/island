import DynamicNotchKit
import SwiftUI
import Testing

/// First-click focus (issue #33): the Island panel is a `.nonactivatingPanel`
/// (ADR-0003), so when Ghostty is frontmost and the Island is not, macOS would
/// swallow the very first `mouseDown` for window ordering and the SwiftUI
/// `.onTapGesture` on a card would never fire on the first click. The vendored
/// hosting view must therefore accept the first mouse, so the first click
/// reaches the tap gesture — and the correct `cardActivated → focusTerminal`
/// chain — without the panel ever becoming activating (the Island never steals
/// focus). Guards the vendored DynamicNotchKit patch.
@MainActor
struct FirstMouseTests {
    @Test("The notch hosting view accepts the first mouse so the first click reaches the card")
    func hostingViewAcceptsFirstMouse() {
        let view = FirstMouseHostingView(rootView: Text("card"))
        #expect(view.acceptsFirstMouse(for: nil) == true)
    }
}
