//
//  NotchlessView.swift
//  DynamicNotchKit
//
//  Created by Kai Azim on 2024-04-06.
//

import SwiftUI

struct NotchlessView<Expanded, CompactLeading, CompactTrailing>: View where Expanded: View, CompactLeading: View, CompactTrailing: View {
    @ObservedObject private var dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing>
    @State private var windowHeight: CGFloat = 0
    /// island patch (issue #145): the hover view's real frame in SwiftUI
    /// global coordinates, so a hover-on reported while the cursor is inside
    /// the half-screen window but OUTSIDE the visible panel (fade-out /
    /// re-creation parasite) can be rejected by a real hit-test. `.zero`
    /// until the first geometry pass — no hit-test then (upstream behaviour).
    @State private var hoverRegion: CGRect = .zero
    private let safeAreaInset: CGFloat = 15

    init(dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing>) {
        self.dynamicNotch = dynamicNotch
    }

    private var cornerRadius: CGFloat {
        if case let .floating(cornerRadius) = dynamicNotch.style {
            cornerRadius
        } else {
            20
        }
    }

    var body: some View {
        notchContent()
            .background {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .padding(20)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { newHeight in
                // This makes sure that the floating window FULLY slides off before disappearing
                windowHeight = newHeight
            }
            .offset(y: dynamicNotch.state == .expanded ? dynamicNotch.notchSize.height : -windowHeight)
            // island patch (issue #145): measure the hover view's REAL frame
            // and hit-test hover-on reports against it. The window spans half
            // the screen, so during the fade-out/re-creation of the panel
            // `onHover` fires a parasite `true` with the cursor well outside
            // the visible panel (up to the window's edge) — the engine of the
            // 0.1.34 residual pump. Not upstream — remove/reconcile if
            // switching back to the package URL.
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { newFrame in
                hoverRegion = newFrame
            }
            .onHover { hovering in
                dynamicNotch.updateHoverState(
                    hovering,
                    within: hoverRegion == .zero ? nil : hoverRegion
                )
            }
    }

    private func notchContent() -> some View {
        VStack(spacing: 0) {
            dynamicNotch.expandedContent
                .transition(.blur(intensity: 10).combined(with: .opacity))
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: safeAreaInset) }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: safeAreaInset) }
                .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: safeAreaInset) }
                .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: safeAreaInset) }
        }
        .fixedSize()
    }
}
