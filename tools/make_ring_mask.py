#!/usr/bin/env python3
"""Маска железа проушины на борту (переправа R2, crossing_panel): где кольцо и пластина ПЕРЕД канатом.

Директор 01.11 (стр. 48: «кольцо всё равно не перекрывает канат нужную часть»): прежде железом считался весь эллипс
вокруг дыры — и там, где канат на рисунке лежит поверх кольца (нижняя правая дуга), бегущий канат упирался в
неподвижный кусок каната с кольцом. Теперь железо — только пиксели самого железа на рисунке (R2_fg_rope_v3, партия 14):
тёмные малонасыщенные внутри эллипса проушины и пластины; канат (оранжевый, насыщенный) — не железо.

    python3 tools/make_ring_mask.py          — записать game/assets/rooms/R2/fg_rope_iron_mask.png
    python3 tools/make_ring_mask.py --check  — сверить (код 1 — не совпадает)
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/incoming/R2_fg_rope_v3.png"
DST = ROOT / "game/assets/rooms/R2/fg_rope_iron_mask.png"
EYE = (1181, 652, 43, 41)          # центр и радиусы с запасом (данные R2 eye: r [41, 39])
BRACKET = (1123, 670, 74, 68)


def build() -> Image.Image:
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    region = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(region)
    cx, cy, rx, ry = EYE
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    bx, by, bw, bh = BRACKET
    d.rectangle((bx, by, bx + bw, by + bh), fill=255)
    px = im.load()
    out = Image.new("L", (w, h), 0)
    po = out.load()
    pr = region.load()
    for y in range(max(0, cy - ry - 2), min(h, by + bh + 2)):
        for x in range(max(0, bx - 2), min(w, cx + rx + 2)):
            if not pr[x, y]:
                continue
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            mx, mn = max(r, g, b), min(r, g, b)
            rope = (r > g > b) and (r - b > 55) and (mx > 90)
            if not rope:
                po[x, y] = 255
    # the hole stays rope: nothing in it is iron (the rope runs through)
    out = out.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    return out


def main() -> int:
    m = build()
    if "--check" in sys.argv:
        cur = Image.open(DST).convert("L") if DST.exists() else None
        ok = cur is not None and ImageChops.difference(cur, m).getbbox() is None
        print("OK" if ok else "DIFF", DST.relative_to(ROOT))
        return 0 if ok else 1
    m.save(DST)
    print("wrote", DST.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
