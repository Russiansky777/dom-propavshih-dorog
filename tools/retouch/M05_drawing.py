"""Рисунок Дуни в крупном плане школьной двери (M05): нужная зарубка бруса обведена от руки чернилами — двойной
неровный овал вокруг третьей метки (Директор 31.10, стр. 38: «на Дунином рисунке понятнее выделить нужную»; брус в
двери теперь со всеми одинаковыми зарубками — tools/retouch/M05_beam.py). Центр метки (454, 791) листа 1672×941."""
from __future__ import annotations

import math

from PIL import Image, ImageDraw, ImageFilter

INK = (52, 36, 24)


def retouch(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    k = 4   # drawn 4× and scaled down: a soft pen line
    w, h = im.size
    layer = Image.new("RGBA", (w * k, h * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = 454.0, 791.0
    for loop, (rx, ry, rot, a0, wid, alpha) in enumerate(((33.0, 41.0, -0.10, -0.35, 3.0, 225), (36.5, 44.0, 0.06, 0.25, 2.2, 170))):
        pts = []
        n = 90
        for i in range(n + 9):   # a little past the start: the pen overlaps where it began
            t = a0 + 2.0 * math.pi * i / n
            wob = 1.0 + 0.035 * math.sin(3.0 * t + loop) + 0.02 * math.sin(7.0 * t + 2.0 * loop)
            x = rx * wob * math.cos(t)
            y = ry * wob * math.sin(t)
            xr = x * math.cos(rot) - y * math.sin(rot)
            yr = x * math.sin(rot) + y * math.cos(rot)
            pts.append(((cx + xr) * k, (cy + yr) * k))
        d.line(pts, fill=INK + (alpha,), width=int(wid * k), joint="curve")
    layer = layer.resize((w, h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.35))
    out = im.copy()
    out.alpha_composite(layer)
    return out
