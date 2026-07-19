//
//  EnvironmentValues+Extensions.swift
//  DynamicNotchKit
//
//  Created by Kai Azim on 2025-03-26.
//

import SwiftUI

// Patched for build with Command Line Tools only (no Xcode): the SwiftUI
// `@Entry` macro plugin is unavailable there, so the environment keys are
// written out explicitly. Behavior is identical to upstream 1.1.0.
private struct NotchStyleEnvironmentKey: EnvironmentKey {
    static let defaultValue: DynamicNotchStyle = .auto
}

private struct NotchSectionEnvironmentKey: EnvironmentKey {
    static let defaultValue: DynamicNotchSection = .expanded
}

extension EnvironmentValues {
    var notchStyle: DynamicNotchStyle {
        get { self[NotchStyleEnvironmentKey.self] }
        set { self[NotchStyleEnvironmentKey.self] = newValue }
    }

    var notchSection: DynamicNotchSection {
        get { self[NotchSectionEnvironmentKey.self] }
        set { self[NotchSectionEnvironmentKey.self] = newValue }
    }
}

enum DynamicNotchSection {
    case expanded
    case compactLeading
    case compactTrailing
}
