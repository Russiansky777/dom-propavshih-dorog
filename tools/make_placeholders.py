#!/usr/bin/env python3
"""Generate placeholder PNGs.

M0 probe:  game/assets/placeholders/*.png (quarter-resolution; scaled x4 in-game).
M1 rooms:  game/assets/placeholders/rooms/<LOC>.png — background per data/story/rooms/<LOC>.json
           (wall/floor/accent colours, horizon, room id + name label). Hotspots, exits and props are
           drawn by the game at runtime from the same JSON, so only the backdrop lives here.
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


ROOMS_DIR = os.path.join(ROOT, "data", "story", "rooms")
ROOMS_OUT = os.path.join(OUT, "rooms")
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
]


def _font(size: int):
    from PIL import ImageFont
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def _hex(c: str) -> tuple:
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def _shade(c: tuple, k: float) -> tuple:
    return tuple(max(0, min(255, int(v * k))) for v in c)


def room_background(room: dict, locations: dict) -> None:
    """Half-resolution (960x540) backdrop: wall, floor with perspective boards, horizon, labels."""
    import json as _json
    bg = room.get("background", {})
    kind = bg.get("kind", "interior")
    wall = _hex(bg.get("wall", "#555555"))
    floor = _hex(bg.get("floor", "#777777"))
    accent = _hex(bg.get("accent", "#444444"))
    horizon = int(bg.get("horizon", 640)) // 2
    w, h = 960, 540
    img = Image.new("RGB", (w, h), wall)
    d = ImageDraw.Draw(img)
    if kind == "exterior":
        # Sky gradient + distant band.
        for y in range(horizon):
            k = 0.85 + 0.3 * (y / max(1, horizon))
            d.line([(0, y), (w, y)], fill=_shade(wall, k))
        d.rectangle([0, horizon - 40, w, horizon], fill=_shade(accent, 0.9))
    else:
        for x in range(0, w, 32):
            d.line([(x, 0), (x, horizon)], fill=_shade(wall, 0.85), width=1)
    d.rectangle([0, horizon - 5, w, horizon], fill=_shade(accent, 0.7))
    d.rectangle([0, horizon, w, h], fill=floor)
    cx = w // 2
    for i in range(-14, 15):
        d.line([(cx + i * 24, horizon), (cx + i * 70, h)], fill=_shade(floor, 0.85), width=1)
    for y in range(horizon, h, 18):
        d.line([(0, y), (w, y)], fill=_shade(floor, 0.85), width=1)
    # Layout of a room whose art is still being drawn (`placeholder` in rooms/<LOC>.json, 1920x1080
    # coordinates): polygons / ellipses with a caption, so the stand-in already shows where the porch,
    # the doors and the way out are (Z4: house porch left, post office door right, street at the back).
    for sh in room.get("placeholder", []):
        col = _hex(sh.get("color", "#888888"))
        if "poly" in sh:
            pts = [(x / 2, y / 2) for x, y in sh["poly"]]
            d.polygon(pts, fill=col, outline=_shade(col, 0.6))
            cx2 = sum(p[0] for p in pts) / len(pts)
            cy2 = sum(p[1] for p in pts) / len(pts)
        elif "ellipse" in sh:
            ex, ey, ew, eh = (v / 2 for v in sh["ellipse"])
            d.ellipse([ex, ey, ex + ew, ey + eh], fill=col, outline=_shade(col, 0.8))
            cx2, cy2 = ex + ew / 2, ey + eh / 2
        else:
            continue
        if sh.get("label"):
            f = _font(16)
            tw = d.textlength(sh["label"], font=f)
            d.text((cx2 - tw / 2, cy2 - 9), sh["label"], fill=(255, 255, 255), font=f,
                   stroke_width=2, stroke_fill=(30, 30, 30))
    rid = room["id"]
    name = locations.get(rid, rid)
    d.text((24, 16), rid, fill=_shade(wall, 1.6), font=_font(56))
    d.text((24, 84), name, fill=_shade(wall, 1.5), font=_font(28))
    os.makedirs(ROOMS_OUT, exist_ok=True)
    path = os.path.join(ROOMS_OUT, f"{rid}.png")
    img.save(path, optimize=True)
    print(f"wrote {os.path.relpath(path, ROOT)} {w}x{h}")


def rooms() -> None:
    import json as _json
    if not os.path.isdir(ROOMS_DIR):
        return
    locs = {}
    loc_path = os.path.join(ROOT, "data", "story", "locations.json")
    if os.path.exists(loc_path):
        with open(loc_path, encoding="utf-8") as f:
            locs = {l["id"]: l["name"] for l in _json.load(f)["locations"]}
    for name in sorted(os.listdir(ROOMS_DIR)):
        if not name.endswith(".json") or name.startswith("_"):
            continue
        with open(os.path.join(ROOMS_DIR, name), encoding="utf-8") as f:
            room = _json.load(f)
        image = room.get("background", {}).get("image", "")
        if image and not image.startswith("res://assets/placeholders/"):
            print(f"skip {room['id']}: real background {image}")
            continue
        room_background(room, locs)


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
    rooms()
    return 0


if __name__ == "__main__":
    sys.exit(main())
