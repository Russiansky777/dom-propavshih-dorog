#!/usr/bin/env python3
"""The game's icon (Director 12.11, 23:35: «Значок — подумай какой и отрисуй»): the lit carved window of the title
picture — a square cut out of `game/assets/ui/menu/title_bg.png` (the game's own art, ASSET_PROVENANCE «главное меню
и пауза») → `game/icon.png`, 256×256. The project's icon (the window, the taskbar) and, through the Windows export
presets (`application/icon`), the exe's icon in six sizes — the engine scales it itself.

    python3 tools/make_icon.py            # write game/icon.png
    python3 tools/make_icon.py --check    # game/icon.png is this cut of the title picture (code 1 if not)

Another cut — change BOX (x, y, side in the title picture's pixels) and run without arguments.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "game" / "assets" / "ui" / "menu" / "title_bg.png"
ICON = ROOT / "game" / "icon.png"
BOX = (1372, 205, 300)   # the window with the lamp behind the lace curtain, the carved frame on both sides
SIZE = 256


def build() -> Image.Image:
    x, y, side = BOX
    src = Image.open(SOURCE).convert("RGB")
    if x + side > src.width or y + side > src.height:
        raise SystemExit(f"make_icon: the cut {BOX} is outside {SOURCE.name} {src.size}")
    return src.crop((x, y, x + side, y + side)).resize((SIZE, SIZE), Image.LANCZOS)


def main(argv: list[str]) -> int:
    want = build()
    if "--check" in argv:
        if not ICON.exists():
            print("make_icon --check: FAILED — no game/icon.png")
            return 1
        got = Image.open(ICON).convert("RGB")
        diff = 255.0 if got.size != want.size else sum(ImageStat.Stat(ImageChops.difference(got, want)).mean) / 3.0
        # self-check: a cut shifted by a tenth of its side is not this icon
        x, y, side = BOX
        other = Image.open(SOURCE).convert("RGB").crop((x - side // 10, y, x - side // 10 + side, y + side)).resize((SIZE, SIZE), Image.LANCZOS)
        far = sum(ImageStat.Stat(ImageChops.difference(other, want)).mean) / 3.0
        if far < 3.0:
            print(f"make_icon --check: self-check FAILED — a shifted cut differs by {far:.1f} only")
            return 1
        if diff > 1.0:
            print(f"make_icon --check: FAILED — game/icon.png is not the cut {BOX} of {SOURCE.name} (difference {diff:.1f} of 255); run tools/make_icon.py")
            return 1
        print(f"make_icon --check: OK — game/icon.png is the cut {BOX} of {SOURCE.name} (difference {diff:.2f}; a shifted cut — {far:.1f})")
        return 0
    want.save(ICON, optimize=True)
    print(f"make_icon: {ICON.relative_to(ROOT)} {want.size} from {SOURCE.name} {BOX}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
