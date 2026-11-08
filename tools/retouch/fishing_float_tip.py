"""Поплавок (партия 14, перо с красной верхушкой): красный кончик ярче и чуть длиннее (Директор 08.11, 20:14: «красный
кончик сделать ярче, а можно и чуть больше тоже»). Красное — пиксели, где R заметно больше G и B; их цвет насыщается
и светлеет (R ×1.18, G и B ×0.72, альфа как была). Кончик удлиняется: непрозрачные пиксели стержня в полосе TIP_GROW px от красного
(расширение маски) берут цвет ближайшего пикселя кончика — его тень и блик продолжаются вниз по стержню. Остальное (стержень, пробка, вода, тень) не трогается."""
from __future__ import annotations

import numpy as np
from PIL import Image

TIP_GROW = 9          # px холста 300 px высотой (на экране при масштабе 0.36 — ≈ 3 px)
BRIGHT = (1.18, 0.72, 0.72)


def _dilate(mask: np.ndarray, r: int) -> np.ndarray:
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            sh = np.zeros_like(mask)
            ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
            xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
            sh[yd, xd] = mask[ys, xs]
            out |= sh
    return out


def retouch(im: Image.Image) -> Image.Image:
    a = np.array(im.convert("RGBA")).astype(np.float32)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    red = (al > 60) & (r > 110) & (g < 110) & (b < 110) & (r - g > 60) & (r - b > 60)
    # the tip only: the red component holding the topmost red pixel (the cork's dark wood is reddish too)
    top = np.nonzero(red)
    seed = np.zeros_like(red)
    seed[top[0].min(), top[1][np.argmin(top[0])]] = True
    comp = seed
    while True:
        nxt = _dilate(comp, 1) & red
        if nxt.sum() == comp.sum():
            break
        comp = nxt
    red = comp
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    grow = _dilate(red, TIP_GROW) & ~red & (al > 200) & (lum > 60)
    # the stem below the tip only — not the water ring or the shadow (they sit far below the tip)
    ys = np.nonzero(red)[0]
    grow &= (np.arange(a.shape[0])[:, None] <= ys.max() + TIP_GROW + 2)
    # each new pixel takes the colour of the nearest tip pixel — the tip's own shading continues down the stem
    ry, rx = np.nonzero(red)
    gy, gx = np.nonzero(grow)
    for y, x in zip(gy, gx):
        k = np.argmin((ry - y) ** 2 + (rx - x) ** 2)
        a[y, x, :3] = a[ry[k], rx[k], :3]
    red2 = red | grow
    a[..., 0][red2] = np.clip(a[..., 0][red2] * BRIGHT[0], 0, 255)
    a[..., 1][red2] = np.clip(a[..., 1][red2] * BRIGHT[1], 0, 255)
    a[..., 2][red2] = np.clip(a[..., 2][red2] * BRIGHT[2], 0, 255)
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")
