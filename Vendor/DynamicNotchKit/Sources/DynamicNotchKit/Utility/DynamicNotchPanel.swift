//
// DynamicNotchPanel.swift
// DynamicNotchKit
//
// Created by <Huy D.> on 2024-11-01.
//

import AppKit
import SwiftUI

/// island patch (issue #33): hosting view that accepts the first mouse.
///
/// The notch is presented in a `.nonactivatingPanel` (see
/// ``DynamicNotchPanel`` / `DynamicNotch.initializeWindow`), so that it never
/// steals focus from the terminal. The side effect is that when the panel's
/// app is not active, macOS treats the very first `mouseDown` as a
/// window-ordering click and swallows it — the SwiftUI content (e.g. a card's
/// `.onTapGesture`) only reacts from the *second* click. Overriding
/// `acceptsFirstMouse(for:)` makes that first click reach the content
/// immediately, without making the panel activating: the Island still never
/// becomes the active app, and the click-to-focus chain fires on the first
/// click. Not upstream — remove/reconcile if switching back to the package URL.
public final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

final class DynamicNotchPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        self.hasShadow = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    override var canBecomeKey: Bool {
        true
    }
}
