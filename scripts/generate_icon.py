#!/usr/bin/env python3
"""Generates the app icon (packaging/island.icns) from the existing `isle`
pixel-art sprite (issue #11, planche C), so the bundle icon and the Island
logo are the same drawing.

The island pixels are reused verbatim from generate_sprites.py (draw_isle) and
composited, nearest-neighbor upscaled, onto a macOS-style rounded-square ocean
background. Re-run after any isle design change, then commit the .icns:

    python3 scripts/generate_icon.py

Requires Pillow (same dependency as generate_sprites.py) and iconutil (Command
Line Tools) to assemble the .icns from the generated .iconset.
"""

import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

# Reuse the isle sprite drawing verbatim — single source of truth for pixels.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_sprites as sprites  # noqa: E402

MASTER = 1024          # macOS icon master size (also the largest iconset tile)
SS = 4                 # supersampling factor for smooth squircle edges
# Ocean gradient echoing the sprite's water tones (WATER #4aa8d8 / GLINT).
SKY = (134, 208, 240)  # top
DEEP = (46, 134, 192)  # bottom
# Apple's icon grid: the rounded square sits inside the canvas with margin for
# the drop shadow, corners at ~22.37% of its side.
MARGIN_RATIO = 0.055
RADIUS_RATIO = 0.2237


def isle_tile():
    """The isle sprite, frame 0, as a 16x16 RGBA tile (transparent ground)."""
    tile = Image.new("RGBA", (sprites.SIZE, sprites.SIZE), (0, 0, 0, 0))
    sprites.draw_isle(sprites.Frame(tile, 0, 0), 0)
    return tile


def vertical_gradient(size, top, bottom):
    """A size×size RGBA vertical gradient, built cheaply then stretched."""
    column = Image.new("RGBA", (1, size))
    for y in range(size):
        t = y / (size - 1)
        column.putpixel(
            (0, y),
            (
                round(top[0] * (1 - t) + bottom[0] * t),
                round(top[1] * (1 - t) + bottom[1] * t),
                round(top[2] * (1 - t) + bottom[2] * t),
                255,
            ),
        )
    return column.resize((size, size))


def make_master():
    big = MASTER * SS
    margin = round(big * MARGIN_RATIO)
    radius = round((big - 2 * margin) * RADIUS_RATIO)
    box = (margin, margin, big - margin - 1, big - margin - 1)

    # Rounded-square mask (supersampled → LANCZOS-smoothed edges).
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)

    gradient = vertical_gradient(big, SKY, DEEP)
    squircle = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    squircle.paste(gradient, (0, 0), mask)

    # Soft drop shadow under the squircle for depth.
    shadow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 110), (0, 0), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(big * 0.02))
    offset = round(big * 0.012)
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    canvas.alpha_composite(shadow, (0, offset))
    canvas.alpha_composite(squircle)

    master = canvas.resize((MASTER, MASTER), Image.LANCZOS)

    # Island: nearest-neighbor upscale keeps the pixels crisp, centered on the
    # squircle with headroom so the palm and water read at a glance.
    scale = 40  # 16 px → 640 px, ~62% of the 1024 canvas
    island = isle_tile().resize(
        (sprites.SIZE * scale, sprites.SIZE * scale), Image.NEAREST
    )
    x = (MASTER - island.width) // 2
    y = (MASTER - island.height) // 2
    master.alpha_composite(island, (x, y))
    return master


# (iconset tile name, pixel size)
ICONSET = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "packaging",
        "island.icns",
    )
    os.makedirs(os.path.dirname(out), exist_ok=True)

    master = make_master()
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "island.iconset")
        os.makedirs(iconset)
        for name, size in ICONSET:
            tile = master if size == MASTER else master.resize(
                (size, size), Image.LANCZOS
            )
            tile.save(os.path.join(iconset, name))
        subprocess.run(
            ["iconutil", "-c", "icns", iconset, "-o", out], check=True
        )
    print(f"wrote {out} from {sprites.SIZE}px isle sprite")


if __name__ == "__main__":
    main()
