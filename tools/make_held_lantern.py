#!/usr/bin/env python3
"""Mitya's lantern in his hand (Director 02.11, стр. 21): the very lantern партии 15 painted at his feet on the far pier
(game/assets/rooms/R3/state_mitya_lantern.png, lit), cut out without its light on the snow — the opaque tin and glass
(alpha ≥ CUT), a 1-px soft edge — and scaled ×SCALE (Lanczos) so it stays crisp on the street too. The glow round it
is drawn by the game (HeldProp, additive), the light on the snow goes with him.

    python3 tools/make_held_lantern.py            → game/assets/props/held_lantern.png (+ prints anchor/glass)
    python3 tools/make_held_lantern.py --check    → exit 1 when the game copy differs
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "game/assets/rooms/R3/state_mitya_lantern.png"
DST = ROOT / "game/assets/props/held_lantern.png"
BOX = (500, 520, 576, 600)
CUT = 170
SCALE = 3


def build() -> Image.Image:
    im = Image.open(SRC).convert("RGBA").crop(BOX)
    a = np.array(im)
    keep = (a[..., 3] >= CUT).astype(np.uint8) * 255
    m = Image.fromarray(keep, "L").filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.6))
    alpha = ImageChops.multiply(im.getchannel("A"), m)
    out = im.copy()
    out.putalpha(alpha)
    bb = out.getbbox()
    out = out.crop(bb)
    return out.resize((out.width * SCALE, out.height * SCALE), Image.LANCZOS)


def main() -> int:
    im = build()
    if "--check" in sys.argv:
        same = DST.exists() and ImageChops.difference(Image.open(DST).convert("RGBA"), im).getbbox() is None
        print(("OK   " if same else "DIFF ") + str(DST.relative_to(ROOT)))
        return 0 if same else 1
    DST.parent.mkdir(parents=True, exist_ok=True)
    im.save(DST, optimize=True)
    a = np.array(im)[..., 3]
    ys, xs = np.nonzero(a > 128)
    top = int(ys.min())
    cx = int(np.median(xs[ys < top + 6]))
    print("wrote", DST.relative_to(ROOT), im.size, "bail top", (cx, top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
