#!/usr/bin/env python3
"""Generates the embedded sprite sheets (issue #11) from the pixel-art
designs validated on planche C ("Bots" + isle logo).

The drawings below are the source of truth for the pixels; the Swift side
only knows the grid (SpriteSheet descriptor: 16 px frames, one row per
animation, one column per frame). Re-run after any design change:

    python3 scripts/generate_sprites.py

Outputs Sources/IslandUI/Resources/Sprites/{bot,isle}.png (transparent
background, no scaling: the app renders them nearest-neighbor).
"""

from PIL import Image

SIZE = 16

# Shared state tints: the sprite carries the #8 Compact tones.
ORANGE = "#f5a136"
GREEN = "#4cd964"
RED = "#e5484d"
ZGREY = "#8b93a1"

GLYPHS = {
    "q": ["##.", "..#", ".#.", "...", ".#."],
    "z": ["###", ".#.", "###"],
    "check": ["....#", "...#.", "#.#..", ".#..."],
}

# Bot palette (planche C).
METAL = "#aeb6c2"
SHADE = "#7d8694"
SCREEN = "#0d1117"
CODE = "#57d47a"

# Animation rows and loops — MUST mirror SpriteSheet.bot and the
# SpriteAnimation declaration order (working, sleeping, finished, question,
# error).
BOT_LOOPS = [("working", 4), ("sleeping", 2), ("finished", 4), ("question", 3), ("error", 6)]


def hex_rgba(color):
    color = color.lstrip("#")
    return tuple(int(color[i : i + 2], 16) for i in (0, 2, 4)) + (255,)


class Frame:
    def __init__(self, image, ox, oy):
        self.image, self.ox, self.oy = image, ox, oy

    def px(self, x, y, color):
        x, y = x + self.ox, y + self.oy
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.image.putpixel((x, y), hex_rgba(color))

    def row(self, y, x0, x1, color):
        for x in range(x0, x1 + 1):
            self.px(x, y, color)

    def glyph(self, name, x, y, color):
        for j, line in enumerate(GLYPHS[name]):
            for i, ch in enumerate(line):
                if ch == "#":
                    self.px(x + i, y + j, color)


def draw_bot(frame, state, f):
    shake = (1 if f % 2 else -1) if state == "error" else 0
    oy = -1 if (state == "finished" and f == 1) else 0
    tip = {
        "working": CODE if f % 2 else SHADE,
        "sleeping": SHADE,
        "finished": GREEN,
        "question": ORANGE,
        "error": RED,
    }[state]

    frame.px(7 + shake, 1 + oy, tip)
    frame.px(7 + shake, 2 + oy, SHADE)
    frame.row(3 + oy, 4 + shake, 11 + shake, METAL)
    for y in range(4, 10):
        frame.px(3 + shake, y + oy, METAL)
        frame.px(12 + shake, y + oy, METAL)
    frame.row(10 + oy, 4 + shake, 11 + shake, SHADE)
    for y in range(4, 10):
        for x in range(4, 12):
            frame.px(x + shake, y + oy, SCREEN)
    frame.px(2 + shake, 6 + oy, SHADE)   # arms
    frame.px(13 + shake, 6 + oy, SHADE)
    frame.px(5, 11, SHADE)               # legs
    frame.px(10, 11, SHADE)
    frame.row(12, 4, 6, METAL)           # feet
    frame.row(12, 9, 11, METAL)

    if state == "working":
        lines = [(4, 6), (8, 10), (5, 9), (4, 7)]
        for r in range(4):
            a, b = lines[(r + f) % len(lines)]
            frame.row(5 + r + oy, a + shake, min(b, 11) + shake, CODE)
    elif state == "sleeping":
        frame.px(7, 6, "#3a4f66" if f % 2 else "#22303f")
        frame.glyph("z", 12, 1, ZGREY)
    elif state == "finished":
        frame.glyph("check", 5 + shake, 5 + oy, GREEN)
    elif state == "question":
        if f % 3 != 2:
            frame.glyph("q", 6 + shake, 4 + oy, ORANGE)
    elif state == "error":
        bars = [(4, 9), (6, 11), (5, 8)]
        for r in range(3):
            a, b = bars[(r + f) % len(bars)]
            frame.row(5 + 2 * r + oy, a + shake, b + shake, RED)


# Extended-card glyphs: the bot screen's glyphs alone, drawn at 2× scale.
# MUST mirror SpriteSheet.glyphs (same animation rows as the bot sheet).
GLYPH_LOOPS = [("working", 4), ("sleeping", 2), ("finished", 4), ("question", 3), ("error", 2)]

CROSS = ["#.#", ".#.", "#.#"]
DOTS = ["#....", "#.#..", "#.#.#"]


def glyph_2x(frame, rows, x0, y0, color, max_cols=99):
    for j, line in enumerate(rows):
        for i, ch in enumerate(line):
            if ch == "#" and i < max_cols:
                for dx in (0, 1):
                    for dy in (0, 1):
                        frame.px(x0 + 2 * i + dx, y0 + 2 * j + dy, color)


def draw_card_glyph(frame, state, f):
    if state == "working":
        # Typing dots appearing one by one.
        frame_rows = [DOTS[min(f, 2)]]
        glyph_2x(frame, frame_rows, 3, 7, CODE)
    elif state == "sleeping":
        glyph_2x(frame, GLYPHS["z"], 5, 4 - f, ZGREY)
    elif state == "finished":
        # The check draws itself left to right, then a glint.
        glyph_2x(frame, GLYPHS["check"], 3, 4, GREEN, max_cols=[3, 4, 5, 5][f])
        if f == 3:
            frame.px(14, 3, "#c9f4e4")
    elif state == "question":
        # Blinks like on the robot's screen; the off frame sits mid-cycle so
        # the sheet contract (non-empty last frame) stays checkable.
        if f != 1:
            glyph_2x(frame, GLYPHS["q"], 5, 3, ORANGE)
    elif state == "error":
        glyph_2x(frame, CROSS, 5 + (1 if f % 2 else -1), 5, RED)


# Isle palette (logo, same style as the bots — shares the code green).
SAND = "#e8d5a9"
SAND_SHADE = "#c9a86a"
TRUNK = "#a97c50"
PALM = "#57d47a"
WATER = "#4aa8d8"
GLINT = "#8fd0ef"


def draw_isle(frame, f):
    frame.row(14, 1, 14, WATER)
    frame.px(2 + (f % 2) * 2, 14, GLINT)
    frame.px(13 - (f % 2) * 2, 14, GLINT)
    frame.row(11, 5, 10, SAND)
    frame.row(12, 4, 11, SAND)
    frame.row(13, 3, 12, SAND_SHADE)
    for x, y in [(8, 10), (8, 9), (8, 8), (7, 7), (7, 6)]:
        frame.px(x, y, TRUNK)
    frame.px(9, 7, TRUNK)  # coconut
    s = f % 2              # palms swaying
    for x, y in [(6, 5), (5, 5 - s), (4, 6 - s), (3, 7 - s)]:
        frame.px(x, y, PALM)
    for x, y in [(8, 5), (9, 5), (10, 6 + s), (11, 7 + s)]:
        frame.px(x, y, PALM)
    for x, y in [(7, 4), (6, 3 + s), (8, 3)]:
        frame.px(x, y, PALM)


def sheet(rows, columns):
    return Image.new("RGBA", (columns * SIZE, rows * SIZE), (0, 0, 0, 0))


def main():
    import os

    out = os.path.join(os.path.dirname(__file__), "..", "Sources", "IslandUI", "Resources", "Sprites")
    os.makedirs(out, exist_ok=True)

    max_frames = max(frames for _, frames in BOT_LOOPS)
    bot = sheet(rows=len(BOT_LOOPS), columns=max_frames)
    for row, (state, frames) in enumerate(BOT_LOOPS):
        for f in range(frames):
            tile = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
            draw_bot(Frame(tile, 0, 0), state, f)
            bot.paste(tile, (f * SIZE, row * SIZE))
    bot.save(os.path.join(out, "bot.png"))

    max_glyph_frames = max(frames for _, frames in GLYPH_LOOPS)
    glyphs = sheet(rows=len(GLYPH_LOOPS), columns=max_glyph_frames)
    for row, (state, frames) in enumerate(GLYPH_LOOPS):
        for f in range(frames):
            tile = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
            draw_card_glyph(Frame(tile, 0, 0), state, f)
            glyphs.paste(tile, (f * SIZE, row * SIZE))
    glyphs.save(os.path.join(out, "glyphs.png"))

    isle = sheet(rows=1, columns=2)
    for f in range(2):
        tile = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        draw_isle(Frame(tile, 0, 0), f)
        isle.paste(tile, (f * SIZE, 0))
    isle.save(os.path.join(out, "isle.png"))
    print(f"wrote {out}/bot.png ({bot.width}x{bot.height}) and isle.png ({isle.width}x{isle.height})")


if __name__ == "__main__":
    main()
