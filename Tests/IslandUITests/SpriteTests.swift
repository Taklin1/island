import CoreGraphics
import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Sprites (issue #11): pure logic of the pixel-art mascots that replace the
/// compact-mode text. Mapping, sheet layout and frame timing are plain
/// functions and are tested here; the pixels themselves are checked visually
/// (PRD #3, Testing Decisions).
@MainActor
struct SpriteTests {
    @Test("Each Session state maps to its Sprite animation")
    func sessionStateMapsToAnimation() {
        #expect(SpriteAnimation.animation(for: .running) == .working)
        #expect(SpriteAnimation.animation(for: .idle) == .sleeping)
        #expect(SpriteAnimation.animation(for: .ended) == .finished)
        #expect(SpriteAnimation.animation(for: .waiting) == .question)
    }

    @Test("Frames advance at the animation's own pace and loop")
    func framesAdvanceAtTheAnimationPaceAndLoop() {
        let sheet = SpriteSheet.bot

        // Working runs at 4 fps over 4 frames: one frame every 250 ms…
        #expect(sheet.frameIndex(for: .working, elapsed: 0) == 0)
        #expect(sheet.frameIndex(for: .working, elapsed: 0.26) == 1)
        #expect(sheet.frameIndex(for: .working, elapsed: 0.9) == 3)
        // …and loops back after a full cycle.
        #expect(sheet.frameIndex(for: .working, elapsed: 1.0) == 0)

        // Sleeping breathes slower (1.5 fps, 2 frames).
        #expect(sheet.frameIndex(for: .sleeping, elapsed: 0) == 0)
        #expect(sheet.frameIndex(for: .sleeping, elapsed: 0.7) == 1)
        #expect(sheet.frameIndex(for: .sleeping, elapsed: 1.4) == 0)

        // A clock going backwards never crashes the loop.
        #expect(sheet.frameIndex(for: .working, elapsed: -1) == 0)
    }

    @Test("A frame lives at its row (animation) and column (frame) in the sheet")
    func frameRectAddressesTheSheetByRowAndColumn() {
        let sheet = SpriteSheet.bot

        #expect(sheet.frameRect(for: .working, frame: 0) == CGRect(x: 0, y: 0, width: 16, height: 16))
        #expect(sheet.frameRect(for: .working, frame: 2) == CGRect(x: 32, y: 0, width: 16, height: 16))
        // Rows follow the declaration order of the animations.
        #expect(sheet.frameRect(for: .question, frame: 1) == CGRect(x: 16, y: 48, width: 16, height: 16))
        #expect(sheet.frameRect(for: .error, frame: 0) == CGRect(x: 0, y: 64, width: 16, height: 16))
    }

    @Test("The compact bar shows one Sprite per Session, in order")
    func compactBarShowsOneSpritePerSession() {
        let sessions = [
            Session(id: "a", state: .running, agent: "claude-code"),
            Session(id: "b", state: .idle, agent: "claude-code"),
            Session(id: "c", state: .waiting, agent: "claude-code"),
        ]

        let sprites = IslandController.compactSprites(for: sessions)

        #expect(sprites.map(\.id) == ["a", "b", "c"])
        #expect(sprites.map(\.animation) == [.working, .sleeping, .question])
        #expect(IslandController.compactSprites(for: []).isEmpty)
    }

    @Test("The embedded sheets match the descriptor's grid")
    func embeddedSheetsMatchTheDescriptorGrid() throws {
        // Bot: one row per animation, one column per frame of the longest loop.
        let bot = try #require(SpriteSheet.bot.image(named: "bot"))
        #expect(bot.width == SpriteSheet.bot.maxFrames * SpriteSheet.frameSize)
        #expect(bot.height == SpriteAnimation.allCases.count * SpriteSheet.frameSize)

        // Isle logo: a single two-frame row (palms swaying).
        let isle = try #require(SpriteSheet.isle.image(named: "isle"))
        #expect(isle.width == SpriteSheet.isle.maxFrames * SpriteSheet.frameSize)
        #expect(isle.height == SpriteSheet.frameSize)

        // Every declared loop is actually drawn: the last frame of each
        // animation holds real pixels (a frame count drifting between the
        // descriptor and the generator would land on a transparent tile).
        for animation in SpriteAnimation.allCases {
            let frames = try #require(SpriteSheet.bot.loops[animation]?.frames)
            let rect = SpriteSheet.bot.frameRect(for: animation, frame: frames - 1)
            #expect(Self.hasVisiblePixels(in: bot, rect: rect), "empty last frame: \(animation)")
        }
    }

    /// Renders one frame into a fresh bitmap and looks for any opaque pixel
    /// (CGImage.cropping shares the parent's backing data, so the crop itself
    /// cannot be inspected directly).
    private static func hasVisiblePixels(in image: CGImage, rect: CGRect) -> Bool {
        guard let frame = image.cropping(to: rect) else { return false }
        let side = Int(rect.width)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(frame, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels.contains { $0 != 0 }
    }
}
