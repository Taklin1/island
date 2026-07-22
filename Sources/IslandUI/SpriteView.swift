import SwiftUI

/// Renders one looping Sprite from an embedded sheet (issue #11): crops the
/// current frame and draws it nearest-neighbor so the pixel art stays sharp.
/// No logic of its own beyond SpriteSheet's tested math — the pixels are
/// checked visually (PRD #3, Testing Decisions).
struct SpriteView: View {
    let sheet: SpriteSheet
    let imageName: String
    let animation: SpriteAnimation
    /// Display size in points; 16 keeps an integer device-pixel scale.
    var size: CGFloat = 16

    /// Sheets are tiny; one decode per process is plenty.
    @MainActor private static var cache: [String: CGImage] = [:]

    private var refreshInterval: TimeInterval {
        1.0 / (sheet.loops[animation]?.fps ?? 1)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            if let frame = frame(at: context.date) {
                Image(decorative: frame, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                Color.clear.frame(width: size, height: size)
            }
        }
    }

    private func frame(at date: Date) -> CGImage? {
        guard let sheetImage = Self.sheetImage(sheet: sheet, named: imageName) else { return nil }
        let index = sheet.frameIndex(
            for: animation,
            elapsed: date.timeIntervalSinceReferenceDate
        )
        return sheetImage.cropping(to: sheet.frameRect(for: animation, frame: index))
    }

    @MainActor private static func sheetImage(sheet: SpriteSheet, named name: String) -> CGImage? {
        if let cached = cache[name] { return cached }
        guard let image = sheet.image(named: name) else { return nil }
        cache[name] = image
        return image
    }
}
