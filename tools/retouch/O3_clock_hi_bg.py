"""Мамины ходики крупно (партия 16б, O3_clock_hi_bg 400×720): справа от цифры 7 остался бледный вертикальный штрих —
след римской «VII» партии 16 (x 156–161, y 284–311 листа). Закрыт тем же кремовым полем циферблата правее (x 166–171)."""
from __future__ import annotations

from PIL import Image, ImageDraw, ImageFilter


def retouch(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    out = im.copy()
    src = im.crop((166, 282, 172, 314))
    mask = Image.new("L", src.size, 0)
    ImageDraw.Draw(mask).rectangle((1, 1, src.size[0] - 2, src.size[1] - 2), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(0.8))
    out.paste(src, (156, 282), mask)
    return out
