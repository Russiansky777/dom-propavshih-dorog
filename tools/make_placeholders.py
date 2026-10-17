#!/usr/bin/env python3
"""Generate tiny placeholder PNGs for the M0 probe.

Output: game/assets/placeholders/*.png (quarter-resolution; scaled x4 in-game).
Requires Pillow. Run from anywhere: python3 tools/make_placeholders.py
"""
from __future__ import annotations

import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    print("Pillow is not available; draw placeholders with Godot primitives instead.")
    sys.exit(2)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "placeholders")

# Quarter resolution of 1920x1080.
W, H = 480, 270
HORIZON = 160  # == 640 px in-game


def save(img: Image.Image, name: str) -> None:
    path = os.path.join(OUT, name)
    img.save(path, optimize=True)
    print(f"wrote {os.path.relpath(path, ROOT)} {img.size[0]}x{img.size[1]}")


def background(wall: tuple, wall_dark: tuple, floor: tuple, floor_dark: tuple, name: str) -> None:
    img = Image.new("RGB", (W, H), wall)
    d = ImageDraw.Draw(img)
    # Wall planks.
    for x in range(0, W, 24):
        d.line([(x, 0), (x, HORIZON)], fill=wall_dark, width=1)
    # Skirting / horizon line.
    d.rectangle([0, HORIZON - 6, W, HORIZON], fill=wall_dark)
    # Floor with perspective boards.
    d.rectangle([0, HORIZON, W, H], fill=floor)
    cx = W // 2
    for i in range(-12, 13):
        x_top = cx + i * 16
        x_bottom = cx + i * 48
        d.line([(x_top, HORIZON), (x_bottom, H)], fill=floor_dark, width=1)
    for y in range(HORIZON, H, 14):
        d.line([(0, y), (W, y)], fill=floor_dark, width=1)
    save(img, name)


def table() -> None:
    img = Image.new("RGBA", (128, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 127, 12], fill=(120, 72, 36, 255))          # top
    d.rectangle([2, 12, 125, 16], fill=(80, 46, 22, 255))          # edge
    d.rectangle([6, 16, 14, 47], fill=(96, 56, 28, 255))           # legs
    d.rectangle([113, 16, 121, 47], fill=(96, 56, 28, 255))
    save(img, "table.png")


def door(open_: bool) -> None:
    img = Image.new("RGBA", (50, 100), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 49, 99], fill=(70, 40, 20, 255))            # frame
    if open_:
        d.rectangle([4, 4, 45, 99], fill=(30, 40, 60, 255))        # dark gap (cold room behind)
        d.polygon([(4, 4), (22, 10), (22, 99), (4, 99)], fill=(150, 100, 50, 255))  # leaf ajar
    else:
        d.rectangle([4, 4, 45, 99], fill=(150, 100, 50, 255))      # leaf
        d.ellipse([36, 50, 41, 55], fill=(230, 200, 90, 255))      # knob
    save(img, "door_open.png" if open_ else "door_closed.png")


def mirror_frame() -> None:
    # 136x96 -> 544x384 in-game; inner hole 120x80 -> 480x320.
    img = Image.new("RGBA", (136, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 135, 95], fill=(160, 120, 50, 255))
    d.rectangle([3, 3, 132, 92], fill=(200, 160, 70, 255))
    d.rectangle([8, 8, 127, 87], fill=(0, 0, 0, 0))
    save(img, "mirror_frame.png")


def latch(open_: bool) -> None:
    img = Image.new("RGBA", (20, 30), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 19, 29], fill=(60, 70, 90, 255))            # plate
    if open_:
        d.rectangle([8, 2, 11, 27], fill=(200, 210, 230, 255))     # bar vertical (released)
    else:
        d.rectangle([2, 13, 17, 16], fill=(200, 210, 230, 255))    # bar horizontal (locked)
    save(img, "latch_open.png" if open_ else "latch_closed.png")


def exit_arrow(flip: bool) -> None:
    img = Image.new("RGBA", (30, 115), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 29, 114], fill=(255, 255, 255, 40))
    if flip:
        d.polygon([(24, 40), (6, 57), (24, 74)], fill=(255, 255, 255, 170))
    else:
        d.polygon([(6, 40), (24, 57), (6, 74)], fill=(255, 255, 255, 170))
    save(img, "exit_left.png" if flip else "exit_right.png")


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    background((120, 80, 50), (96, 62, 38), (150, 110, 64), (122, 88, 50), "bg_house.png")
    background((70, 84, 104), (54, 66, 84), (92, 104, 122), (74, 86, 104), "bg_office.png")
    table()
    door(False)
    door(True)
    mirror_frame()
    latch(False)
    latch(True)
    exit_arrow(False)
    exit_arrow(True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
