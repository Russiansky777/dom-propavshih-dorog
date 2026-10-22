#!/usr/bin/env python3
"""Стекло зеркала конторы в тётиной стойке «ЗМ» — слой H2 из готового фона (Директор 23.10 00:03).

Стойка «ЗМ» — высокая резная рама посреди мастерской (рисунок H2_bg.png, партия 1): «рама новая почти
нереальна к нахождению, нужно поменять её с основной рамой». До установки рама пустая (сквозь неё видна стена
и доска за ней); после — в её проёме стекло зеркала конторы. Отдельный рисунок не заказан (координатор:
сначала попробовать самим) — слой строится из фона:

  * проём рамы замерен по пикселям фона (H2_bg 1672×941): внутренняя кромка слева x 1016 (губка рамы
    1013–1015), справа x 1168 (губка 1169–1172), верх y 199 слева / 197 справа (тень под карнизом рамы
    199–202), низ y 518 (блик нижней перекладины 519) — PROJ ниже;
  * стекло — серебристо-серое, тёплое от света мастерской: основа светлее вверху, к низу темнее; в нём
    размытое, обесцвеченное отражение тёплой мастерской (пол и левый верстак фона, отражены по горизонтали),
    мягкий вертикальный блик слева от середины и тонкая вторая полоса; зерно мазка — высокие частоты
    штукатурки фона за рамой (то же письмо, что у рисунка), тень губки рамы по краям и под карнизом.

Запуск: python3 tools/make_h2_frame_glass.py          — записать game/assets/rooms/H2/state_frame_glass.png
        python3 tools/make_h2_frame_glass.py --check  — сверить файл с тем, что дал бы запуск (код 1 — расходятся)
Нужны Pillow и numpy.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
BG = ROOT / "game/assets/rooms/H2/bg.png"
OUT = ROOT / "game/assets/rooms/H2/state_frame_glass.png"

# Проём рамы на холсте фона (по часовой от левого верхнего угла) — тот же контур в rooms/H2.json
# stand_zm.mechanic.frame.glass_polygon.
PROJ = [(1016, 199), (1168, 197), (1168, 518), (1016, 518)]


def build() -> Image.Image:
    bg = Image.open(BG).convert("RGB")
    w, h = bg.size
    x0 = min(p[0] for p in PROJ)
    y0 = min(p[1] for p in PROJ)
    x1 = max(p[0] for p in PROJ) + 1
    y1 = max(p[1] for p in PROJ) + 1
    gw, gh = x1 - x0, y1 - y0
    yy, xx = np.mgrid[0:gh, 0:gw].astype(np.float32)
    u = xx / max(gw - 1, 1)
    v = yy / max(gh - 1, 1)

    # Основа: серебро в тёплом свете мастерской (фон стены за рамой ≈ (109, 74, 46)).
    top = np.array([138, 126, 110], np.float32)
    bottom = np.array([78, 66, 54], np.float32)
    base = top[None, None, :] * (1 - v[..., None] ** 1.2) + bottom[None, None, :] * (v[..., None] ** 1.2)
    # Свет из двери слева (тёплый) — чуть теплее и светлее у левого края.
    warm = np.array([1.06, 1.0, 0.9], np.float32)
    side = (1 - u)[..., None] ** 2
    base = base * (1 + (warm[None, None, :] - 1) * side) * (1 + 0.06 * side)

    # Отражение мастерской: пол и левый верстак фона, по горизонтали наоборот, размыто и обесцвечено.
    refl_src = bg.crop((120, 330, 120 + gw * 3, 330 + gh * 2)).transpose(Image.FLIP_LEFT_RIGHT)
    refl = refl_src.resize((gw, gh), Image.LANCZOS).filter(ImageFilter.GaussianBlur(6))
    r = np.asarray(refl, np.float32)
    lum = r.mean(axis=2, keepdims=True)
    r = lum + (r - lum) * 0.6                      # серебро приглушает краски мастерской
    base = base * 0.6 + (r * 1.05 + 14) * 0.4

    # Мягкий вертикальный блик слева от середины и тонкая вторая полоса; оба слегка наклонены.
    def band(center: float, width: float, tilt: float) -> np.ndarray:
        c = center + tilt * (v - 0.5)
        return np.exp(-((u - c) / width) ** 2)
    hl = 0.55 * band(0.36, 0.10, -0.06) + 0.22 * band(0.62, 0.025, -0.05)
    hl *= 0.75 + 0.25 * np.sin(np.pi * v)          # к краям по высоте блик гаснет
    base = base + hl[..., None] * np.array([58, 56, 50], np.float32)[None, None, :]

    # Зерно мазка: высокие частоты штукатурки за рамой (тем же письмом, что фон).
    wall = np.asarray(bg.crop((x0, y0, x1, y1)).convert("L"), np.float32)
    wall_blur = np.asarray(bg.crop((x0, y0, x1, y1)).convert("L").filter(ImageFilter.GaussianBlur(3)), np.float32)
    grain = (wall - wall_blur)
    base = base + grain[..., None] * 0.35

    # Тень губки рамы: по краям проёма и гуще под карнизом (свет сверху-слева).
    d_left = xx
    d_right = gw - 1 - xx
    top_edge = PROJ[0][1] + (PROJ[1][1] - PROJ[0][1]) * u - y0
    d_top = yy - top_edge
    d_bot = gh - 1 - yy
    shade = (np.exp(-d_left / 5.0) * 0.30 + np.exp(-d_right / 4.0) * 0.38 +
             np.exp(-np.clip(d_top, 0, None) / 8.0) * 0.55 + np.exp(-d_bot / 4.0) * 0.25)
    base = base * (1 - np.clip(shade, 0, 0.7))[..., None]

    rgb = np.clip(base, 0, 255).astype(np.uint8)

    # Маска проёма (с полупиксельным сглаживанием: рисуем в 4× и уменьшаем).
    k = 4
    m = Image.new("L", (gw * k, gh * k), 0)
    ImageDraw.Draw(m).polygon([((x - x0) * k, (y - y0) * k) for x, y in PROJ], fill=255)
    mask = m.resize((gw, gh), Image.LANCZOS)

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glass = Image.fromarray(rgb, "RGB").convert("RGBA")
    glass.putalpha(mask)
    out.paste(glass, (x0, y0))
    return out


def main() -> int:
    img = build()
    if "--check" in sys.argv:
        if not OUT.exists():
            print(f"нет {OUT.relative_to(ROOT)}")
            return 1
        cur = np.asarray(Image.open(OUT).convert("RGBA"), np.int16)
        new = np.asarray(img, np.int16)
        diff = int(np.abs(cur - new).max()) if cur.shape == new.shape else 999
        print(f"{OUT.relative_to(ROOT)}: макс. расхождение {diff}")
        return 0 if diff <= 2 else 1
    img.save(OUT, optimize=True)
    print(f"записан {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
