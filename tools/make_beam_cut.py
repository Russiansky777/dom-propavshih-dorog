#!/usr/bin/env python3
"""Надпись ножом на торце бревна (эпилог EP_beam) из шрифта — вместо нарисованной, пока нет арта.

Директор 25.10 стр. 165: «вырезать Дуня — зачем Дуня, заменить на Агата логичнее»; арт партии 8 (cut_dunya.png)
вырезан «Дуня». Этот скрипт рисует ту же резьбу кодом: буквы — канавка в торце (освещение сверху слева, как на
картине: верхняя/левая стенка канавки в тени, нижняя/правая — на свету, дно тёмное), цвет берётся из самой
древесины фона, края мягкие. Размер и место — как у прежней надписи (bbox слоя cut_dunya).

Запуск: python3 tools/make_beam_cut.py "Агата" game/assets/rooms/EP_beam/cut_agata.png
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BG = ROOT / "game" / "assets" / "rooms" / "EP_beam" / "bg.png"
FONT = ROOT / "game" / "assets" / "fonts" / "old_standard_tt" / "OldStandard-Bold.ttf"
BOX = (540, 380, 850, 522)   # bbox прежней надписи «Дуня» на холсте 1672×941


def blur(a: np.ndarray, r: float) -> np.ndarray:
    im = Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), dtype=np.float32) / 255.0


def main() -> int:
    text = sys.argv[1] if len(sys.argv) > 1 else "Агата"
    out = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "game" / "assets" / "rooms" / "EP_beam" / "cut_agata.png"
    bg = np.asarray(Image.open(BG).convert("RGB"), dtype=np.float32) / 255.0
    H, W = bg.shape[:2]
    bw, bh = BOX[2] - BOX[0], BOX[3] - BOX[1]
    # Fit the word into the old box (a little narrower: «Агата» is one letter longer).
    size = 140
    font = ImageFont.truetype(str(FONT), size)
    while True:
        l, t, r, b = font.getbbox(text)
        if (r - l) <= bw * 1.02 and (b - t) <= bh * 0.95:
            break
        size -= 2
        font = ImageFont.truetype(str(FONT), size)
    l, t, r, b = font.getbbox(text)
    cx, cy = (BOX[0] + BOX[2]) / 2, (BOX[1] + BOX[3]) / 2
    ox, oy = cx - (l + r) / 2, cy - (t + b) / 2 + 6
    m_img = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m_img).text((ox, oy), text, font=font, fill=255)
    # A knife cut is a little rough: wobble the edge by a soft noise.
    rng = np.random.default_rng(165)
    noise = blur(rng.random((H, W)).astype(np.float32), 1.2)
    # The knife takes a wider groove than the font's hairlines: thicken the strokes by ~1.5 px.
    m_img = m_img.filter(ImageFilter.MaxFilter(3))
    mask = np.asarray(m_img, dtype=np.float32) / 255.0
    mask = np.clip((blur(mask, 0.9) - 0.5 + (noise - 0.5) * 0.35) * 3.0 + 0.5, 0, 1)
    # Depth: deepest along the middle of each stroke (a V cut), 0 at the edge.
    depth = blur(mask, 2.8) * mask
    gy, gx = np.gradient(depth)
    # Light from the upper left (as the painting): the wall that faces down-right is lit.
    light = np.array([-0.6, -0.8])
    shade = -(gx * light[0] + gy * light[1]) * 24.0        # >0 lit wall, <0 shadowed wall
    base = bg * 0.56 * np.array([1.0, 0.88, 0.74])            # the groove's floor: darker, warmer wood
    lit = np.clip(shade, 0, 1)[..., None]
    dark = np.clip(-shade, 0, 1)[..., None]
    col = base * (1.0 - 0.6 * dark) + (np.clip(bg * 1.22, 0, 1) - base) * lit
    # A thin dark rim where the knife went in.
    edge = np.clip(blur(mask, 1.0) - blur(mask, 2.6), 0, 1) * 1.6
    col = col * (1.0 - 0.35 * np.clip(edge, 0, 1)[..., None])
    alpha = np.clip(blur(mask, 0.6) * 1.15, 0, 1)
    rgba = np.dstack([np.clip(col, 0, 1), alpha])
    Image.fromarray((rgba * 255.0).astype(np.uint8), "RGBA").save(out, optimize=True)
    print(f"{out.relative_to(ROOT)}: «{text}», шрифт {size} px, bbox {Image.open(out).getbbox()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
