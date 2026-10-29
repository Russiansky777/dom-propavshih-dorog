#!/usr/bin/env python3
"""Иконка «Дёготь» до арта партии 10д (J, Р5): кувшин с дёгтем, вырезанный из фона мастерской H2 (верстак у ящика
«Петли»), на прозрачном квадрате 192×192, как иконки tools/sync_icons.sh. Когда придёт icon_tar партии 10д —
tools/sync_icons.sh tar=assets/incoming/<файл>.png перепишет этот файл.
Запуск из корня: python3 tools/make_tar_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
BG = ROOT / "game" / "assets" / "rooms" / "H2" / "bg.png"
OUT = ROOT / "game" / "assets" / "icons" / "tar.png"
SIZE = 192
# Контур кувшина в пикселях фона H2 (1672×941): горло, тулово, обе ручки.
JUG = [(620, 376), (624, 372), (651, 371), (656, 374), (659, 382), (656, 392), (652, 394), (653, 400), (647, 407),
       (631, 407), (624, 400), (623, 394), (619, 392), (617, 384)]


def main() -> int:
    bg = Image.open(BG).convert("RGBA")
    x0 = min(p[0] for p in JUG) - 2
    y0 = min(p[1] for p in JUG) - 2
    x1 = max(p[0] for p in JUG) + 3
    y1 = max(p[1] for p in JUG) + 3
    crop = bg.crop((x0, y0, x1, y1))
    k = 8
    big = crop.resize((crop.width * k, crop.height * k), Image.LANCZOS)
    m = Image.new("L", big.size, 0)
    ImageDraw.Draw(m).polygon([((x - x0) * k, (y - y0) * k) for x, y in JUG], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(k * 0.6))
    big.putalpha(m)
    fit = 150.0 / max(big.width, big.height)
    big = big.resize((round(big.width * fit), round(big.height * fit)), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sh = Image.new("RGBA", big.size, (0, 0, 0, 0))
    sh.putalpha(big.getchannel("A").point(lambda a: int(a * 0.45)))
    sh = sh.filter(ImageFilter.GaussianBlur(4))
    pos = ((SIZE - big.width) // 2, (SIZE - big.height) // 2)
    out.alpha_composite(sh, (pos[0] + 4, pos[1] + 6))
    out.alpha_composite(big, pos)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT, optimize=True)
    print("wrote", OUT.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
