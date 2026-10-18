#!/usr/bin/env python3
"""Bag icon «Родные петли» — the set of three, composed from the very hinge the door close-up uses.

Why not a generated picture: the Meshy text-to-image attempt (pipeline run 39087095862) drew one or two
hinges, never clearly three, and a different hinge shape than the door. The icon must match the
close-up (Director 18.10: «петли у нас две, а на рисунке и двери — три»), so it is built from
assets/incoming/M05_hinge.png (ChatGPT v1, the hinge of school_door_fit): three copies fanned out with
a soft shadow, same painterly look as the other icons.

    python3 tools/make_icon_hinges.py            → assets/icons/door_hinges.png (1024², RGBA)
    tools/sync_icons.sh door_hinges              → game copy at slot size
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/incoming/M05_hinge.png"
DST = ROOT / "assets/icons/door_hinges.png"
CANVAS = 1024
HINGE_H = 520            # height of one hinge in the icon
FAN = [(-9, -270, 24), (0, 0, -12), (9, 270, 24)]  # (degrees, dx, dy): three separate hinges, countable at slot size


def solid_bbox(im: Image.Image, cut: int = 24) -> tuple[int, int, int, int]:
    """Bounding box of the visible object: the source PNG has faint alpha noise far from the hinge."""
    return im.getchannel("A").point(lambda v: 255 if v > cut else 0).getbbox()


def hinge() -> Image.Image:
    im = Image.open(SRC).convert("RGBA")
    im = im.crop(solid_bbox(im))
    if im.width > im.height:          # the door holds it upright (pin vertical)
        im = im.rotate(90, expand=True)
    k = HINGE_H / im.height
    return im.resize((max(1, round(im.width * k)), HINGE_H), Image.LANCZOS)


def main() -> int:
    h = hinge()
    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    for deg, dx, dy in FAN:
        r = h.rotate(deg, resample=Image.BICUBIC, expand=True)
        x = (CANVAS - r.width) // 2 + dx
        y = (CANVAS - r.height) // 2 + dy
        # soft shadow: light from the upper left, like the other icons
        a = r.getchannel("A").point(lambda v: int(v * 0.45))
        sh = Image.new("RGBA", r.size, (20, 12, 6, 0))
        sh.putalpha(a)
        sh = sh.filter(ImageFilter.GaussianBlur(14))
        out.alpha_composite(sh, (x + 18, y + 22))
        out.alpha_composite(r, (x, y))
    bbox = solid_bbox(out, 8)
    # keep the object ~80 % of the frame, centred
    obj = out.crop(bbox)
    k = 0.82 * CANVAS / max(obj.size)
    obj = obj.resize((round(obj.width * k), round(obj.height * k)), Image.LANCZOS)
    final = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    final.alpha_composite(obj, ((CANVAS - obj.width) // 2, (CANVAS - obj.height) // 2))
    DST.parent.mkdir(parents=True, exist_ok=True)
    final.save(DST)
    print(f"[icon] {DST.relative_to(ROOT)} {final.size} from {SRC.relative_to(ROOT)} ×3")
    return 0


if __name__ == "__main__":
    sys.exit(main())
