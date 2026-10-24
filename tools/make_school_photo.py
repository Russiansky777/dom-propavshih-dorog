#!/usr/bin/env python3
"""T8, п. 4 (ИИ-осмотр 24.10: «Снимок школы» в H3 показывает пристань): в рамке на стене галереи нарисованы озеро и
причал, а подпись и осмотр — «Школа, её крыльцо и дверь…». Без нового арта: в ту же рамку — старый снимок школьного
крыльца с дверью, кроп с фона школьного двора O2 (крыльцо, дверь, перила), в сепии и тоне прежнего снимка (среднее и
разброс яркости, оттенок — по нарисованной картинке), чуть смягчён под живопись.

  game/assets/rooms/H3/state_photo_school.png — полный холст 1672×941, картинка только в проёме паспарту рамки.

Запуск: python3 tools/make_school_photo.py           — записать слой
        python3 tools/make_school_photo.py --check   — сверить с репозиторием (код 1 — расходится)
Нужны Pillow, numpy (не в CI: результат в репозитории).
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ROOMS = ROOT / "game" / "assets" / "rooms"
OUT = ROOMS / "H3" / "state_photo_school.png"
BOX = (938, 236, 1035, 325)        # проём паспарту в рамке на стене (пиксели фона H3, 1672×941)
SRC_BOX = (80, 34, 762, 660)       # крыльцо школы с дверью на фоне O2 (те же пиксели фона)


def build() -> Image.Image:
    h3 = np.array(Image.open(ROOMS / "H3" / "bg.png").convert("RGB"), float)
    old = h3[BOX[1]:BOX[3], BOX[0]:BOX[2]]
    lum_old = old @ [0.299, 0.587, 0.114]
    tint = old.reshape(-1, 3).mean(0) / max(1.0, lum_old.mean())
    w, h = BOX[2] - BOX[0], BOX[3] - BOX[1]
    src = Image.open(ROOMS / "O2" / "bg.png").convert("L").crop(SRC_BOX).resize((w, h), Image.LANCZOS)
    lum = np.array(src.filter(ImageFilter.GaussianBlur(0.5)), float)
    lum = (lum - lum.mean()) / max(1.0, lum.std()) * lum_old.std() + lum_old.mean()
    yy, xx = np.mgrid[0:h, 0:w]
    vign = 1.0 - 0.18 * (((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)   # старый снимок: края темнее
    rgb = np.clip(lum[..., None] * vign[..., None] * tint, 0, 255).astype(np.uint8)
    canvas = Image.new("RGBA", (1672, 941), (0, 0, 0, 0))
    canvas.paste(Image.fromarray(rgb, "RGB").convert("RGBA"), BOX[:2])
    return canvas


def main() -> int:
    im = build()
    if "--check" in sys.argv:
        ok = OUT.exists() and np.abs(np.array(Image.open(OUT).convert("RGBA"), int) - np.array(im, int)).max() <= 2
        if not ok:
            print(f"[photo] расходится: {OUT.relative_to(ROOT)}")
        return 0 if ok else 1
    im.save(OUT, optimize=True)
    print(f"[photo] {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
