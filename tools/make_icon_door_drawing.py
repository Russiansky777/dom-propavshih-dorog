#!/usr/bin/env python3
"""Bag icon «Дунин рисунок посадки» — the very sheet the school-door close-up shows (M05 drawing).

Director 02.11, стр. 8: «чертежи Агата не подбирает, а только смотрит — не добавить ли их в инвентарь, а как
дверь откроем — убрать». The icon is cut from the game's own copy of the drawing
(game/assets/puzzle/M05/drawing.png, made by tools/retouch_art.py from assets/incoming/M05_drawing.png): the
paper sheet trimmed to its visible pixels, turned a few degrees like a loose sheet, a soft shadow from the upper
left as the other icons, fitted into the bag's 192 px square. 0 credits; assets/ is not touched.

    python3 tools/make_icon_door_drawing.py            → game/assets/icons/door_drawing.png
    python3 tools/make_icon_door_drawing.py --check    → exit 1 when the game copy differs
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "game/assets/puzzle/M05/drawing.png"
DST = ROOT / "game/assets/icons/door_drawing.png"
SIZE = 192
WORK = 1024
TILT_DEG = 4.0


def build() -> Image.Image:
    im = Image.open(SRC).convert("RGBA")
    solid = im.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    sheet = im.crop(solid)
    k = (WORK * 0.86) / max(sheet.size)
    sheet = sheet.resize((round(sheet.width * k), round(sheet.height * k)), Image.LANCZOS)
    sheet = sheet.rotate(TILT_DEG, resample=Image.BICUBIC, expand=True)
    out = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    x = (WORK - sheet.width) // 2
    y = (WORK - sheet.height) // 2
    shadow = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    shadow.putalpha(sheet.getchannel("A").point(lambda v: int(v * 0.45)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    out.alpha_composite(shadow, (x + 14, y + 18))
    out.alpha_composite(sheet, (x, y))
    out = out.crop(out.getbbox())
    side = max(out.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.alpha_composite(out, ((side - out.width) // 2, (side - out.height) // 2))
    m = round(side * 0.04)
    pad = Image.new("RGBA", (side + 2 * m, side + 2 * m), (0, 0, 0, 0))
    pad.alpha_composite(sq, (m, m))
    return pad.resize((SIZE, SIZE), Image.LANCZOS)


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
