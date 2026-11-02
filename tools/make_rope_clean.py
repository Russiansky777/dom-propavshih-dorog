#!/usr/bin/env python3
"""The crossing rope without the iron (Director 02.11, стр. 20: «канат и кольцо — так и не пофикшено»).

The crossing (crossing_panel) slides the painted rope of R2_fg_rope_v4 back along its line while the boat is hauled.
That layer has the ring's iron painted in it, so the sliding strands carried rust-coloured iron with them (the «рыжее
пятно» by the ring) and the rope in the eye looked thinner than outside. Партия 17 split the iron into
R2_ring_back (behind the rope) and R2_ring_front (in front); the game now draws ring_back → the sliding rope →
ring_front. This tool makes the rope layer for that: v4 with every iron pixel (either ring layer's alpha) replaced by
the rope one twist further along the rope (period PERIOD px, direction from the vanishing point to the ring), where that
pixel is rope; elsewhere transparent.

    python3 tools/make_rope_clean.py            → game/assets/rooms/R2/fg_rope_clean.png
    python3 tools/make_rope_clean.py --check    → exit 1 when the game copy differs
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/incoming/R2_fg_rope_v4.png"
BACK = ROOT / "assets/incoming/R2_ring_back.png"
FRONT = ROOT / "assets/incoming/R2_ring_front.png"
DST = ROOT / "game/assets/rooms/R2/fg_rope_clean.png"
VP = (780.0, 382.0)        # rooms/R2.json crossing vp (canvas px)
RING = (1166.0, 660.0)     # crossing ring
PERIOD = 34.0              # twist_px


def is_rope(px) -> bool:
    r, g, b, a = (int(v) for v in px)
    return a > 128 and r > g > b and (r - b) > 45 and max(r, g, b) > 80


def build() -> Image.Image:
    src = np.array(Image.open(SRC).convert("RGBA"))
    iron = np.maximum(np.array(Image.open(BACK).convert("RGBA"))[..., 3], np.array(Image.open(FRONT).convert("RGBA"))[..., 3])
    out = src.copy()
    dx, dy = RING[0] - VP[0], RING[1] - VP[1]
    n = math.hypot(dx, dy)
    ux, uy = dx / n, dy / n
    ys, xs = np.nonzero(iron > 8)
    h, w = iron.shape
    for y, x in zip(ys, xs):
        done = False
        for step in (1, -1, 2, -2, 3, -3):
            sx = int(round(x + ux * PERIOD * step))
            sy = int(round(y + uy * PERIOD * step))
            if 0 <= sx < w and 0 <= sy < h and iron[sy, sx] <= 8 and is_rope(src[sy, sx]):
                out[y, x] = src[sy, sx]
                done = True
                break
        if not done:
            out[y, x] = (0, 0, 0, 0)
    return Image.fromarray(out, "RGBA")


def main() -> int:
    im = build()
    if "--check" in sys.argv:
        same = DST.exists() and ImageChops.difference(Image.open(DST).convert("RGBA"), im).getbbox() is None
        print(("OK   " if same else "DIFF ") + str(DST.relative_to(ROOT)))
        return 0 if same else 1
    im.save(DST, optimize=True)
    print("wrote", DST.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
