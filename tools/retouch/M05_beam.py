"""Брус порога в крупном плане школьной двери (M05): нужная зарубка нарисована клином «V», остальные три — прямые
пазы, и ответ виден на самом брусе (Директор 31.10, стр. 38: «бревно сделать одинаковым, а на Дунином рисунке
понятнее выделить нужную»). Клин (x 912–958, y 750–815 листа 1671×941) закрыт тем же куском бруса со второй, прямой
зарубкой (x 714–760) — все четыре одинаковые; какая нужна — только по рисунку Дуни."""
from __future__ import annotations

from PIL import Image, ImageDraw, ImageFilter


def retouch(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    out = im.copy()
    src = im.crop((714, 748, 760, 818))
    mask = Image.new("L", src.size, 0)
    ImageDraw.Draw(mask).rectangle((2, 0, src.size[0] - 3, src.size[1] - 1), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    # keep the sheet's own alpha (the beam's top edge against the transparent sheet)
    out.paste(src, (912, 748), mask)
    return out
