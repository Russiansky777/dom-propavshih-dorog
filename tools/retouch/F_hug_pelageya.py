"""Правка кадра F_hug_pelageya (объятие Пелагеи и Мити, M18): у Пелагеи из-под юбки три сапога — генератор
нарисовал лишнюю ногу (Директор 31.10, стр. 85: «у Пелагеи на кадре с Митей три ноги»). Левый, отдельный сапог
(x 504–557, y 592–668 холста 1672×941) закрыт снегом: верх — снег из-за ног справа от них (622–662 × 594–642,
растянут по ширине), низ — освещённый наст левее фонаря (360–413 × 644–668); край к правому сапогу жёсткий, снег
подогрет к свету фонаря по полосе слева (496–503 × 600–650). Остаются два сапога — пара под юбкой.
Вызов — tools/import_room_art.py по полю art_source.retouch комнаты (оригинал в assets/incoming не меняется)."""
from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def retouch(im: Image.Image) -> Image.Image:
    im = im.convert("RGB")
    out = im.copy()
    x0, y0, w, h = 504, 592, 53, 76
    up = im.crop((622, 594, 662, 642)).resize((w, 58), Image.BICUBIC)
    low = im.crop((360, 644, 413, 668))
    patch = Image.new("RGB", (w, h))
    patch.paste(low, (0, 52))
    upm = Image.new("L", (w, 58), 255)
    d0 = ImageDraw.Draw(upm)
    for i in range(8):
        d0.line([(0, 57 - i), (w, 57 - i)], fill=int(255 * i / 8))
    patch.paste(up, (0, 0), upm)
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    poly = [(509, 593), (556, 593), (556, 666), (506, 666), (504, 640)]
    d.polygon([(x - x0, y - y0) for x, y in poly], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.4))
    px = mask.load()
    for y in range(3, h - 4):
        for x in range(w - 5, w - 3):
            px[x, y] = 255
    p = np.asarray(patch).astype(float)
    left = np.asarray(im.crop((496, 600, 503, 650))).astype(float).reshape(-1, 3).mean(0)
    mine = p[8:58, 3:10].reshape(-1, 3).mean(0)
    ramp = np.clip(1.0 - np.arange(w) / float(w * 0.9), 0, 1)[None, :, None]
    gain = (left / np.maximum(mine, 1))[None, None, :]
    p = p * (1 + (gain - 1) * ramp)
    patch = Image.fromarray(np.clip(p, 0, 255).astype("uint8"))
    out.paste(patch, (x0, y0), mask)
    return out
