#!/usr/bin/env python3
"""G28 (Директор 23.10: «канат натягиваем на берегу, а его там нет — он на табличке с причалом»): после узла на кольце
плиты (M15) канат моста больше не сидит на стопоре Пелагеи. Этот скрипт снимает нарисованный канат со стопора на
ближнем причале R1 — слой-заплатка поверх кадра, без каната от стопора до середины реки (дальний конец у того
берега остаётся: туда же приходит канат от плиты у поворота — его рисует игра, effects R1 rope_from_turn).

  state_stopper_empty_day.png  — днём (фон R1 + настил + вода у берега), дни 3–4;
  state_stopper_empty_dusk.png — в сумерках и вечером (то же + слой dusk), вечер дня второго и третьего.

Канат на фоне находится по самой тёплой (R−B) точке у прямой от стопора (1295, 410) к дальнему столбу (665, 345) в
пикселях фона 1672×941; снимается участок до x 1285 (днём от x 680 — столба того берега, в сумерках от 820 — левее канат под слоями того берега far_*), маска ±3 px, заливка —
cv2.inpaint (Telea) по соседним пикселям собранного кадра. Железное кольцо стопора и швартов лодки не трогаются.

Запуск: python3 tools/make_rope_layers.py          — записать слои в game/assets/rooms/R1/
        python3 tools/make_rope_layers.py --check  — сверить (код 1 — расходятся)
Нужны Pillow, numpy, opencv (не в CI: результат в репозитории).
"""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
R1 = ROOT / "game" / "assets" / "rooms" / "R1"
NEAR = (1295.0, 410.0)     # кольцо стопора на столбе причала
FAR = (665.0, 345.0)       # столб на том берегу
X1 = 1285                  # снимаемый участок каната — до кольца стопора; начало (X0) — по состоянию:
#   днём — от самого столба того берега (680), в сумерках — от 820 (левее канат и так под слоями того берега far_*)
HALF = 3                   # полутолщина маски, px
SAG = 22.0                 # провис каната посередине пролёта, px фона (измерен по рисунку)


def compose(names: list[str]) -> np.ndarray:
    im = Image.open(R1 / "bg.png").convert("RGBA")
    for n in names:
        im.alpha_composite(Image.open(R1 / f"{n}.png").convert("RGBA"))
    return np.array(im.convert("RGB"))


def rope_mask(rgb: np.ndarray, X0: int) -> np.ndarray:
    """Канат — тёплая (бурая) нить на серо-голубой воде: по каждому столбцу — строка с наибольшим R−B у прямой
    стопор—столб, сглаженная по соседним столбцам (канат провисает плавно)."""
    f = rgb.astype(np.float32)
    warm = cv2.GaussianBlur(f[:, :, 0] - f[:, :, 2], (3, 3), 0)
    ys = []
    for x in range(X0, X1 + 1):
        t = (x - FAR[0]) / (NEAR[0] - FAR[0])
        y0 = FAR[1] + t * (NEAR[1] - FAR[1]) + SAG * 4.0 * t * (1.0 - t)   # канат провисает к середине
        lo, hi = int(y0) - 10, int(y0) + 10
        ys.append(lo + int(np.argmax(warm[lo:hi, x])))
    ys = np.convolve(np.pad(np.array(ys, np.float32), 6, mode="edge"), np.ones(13) / 13, mode="valid")
    mask = np.zeros(f.shape[:2], np.uint8)
    for i, x in enumerate(range(X0, X1 + 1)):
        half = HALF + (2 if x > 1150 else (1 if x > 1000 else 0))   # к стопору канат толще
        y = int(round(ys[i]))
        mask[y - half:y + half + 1, x] = 255
    return cv2.dilate(mask, np.ones((3, 3), np.uint8))


def patch(names: list[str], x0: int) -> Image.Image:
    rgb = compose(names)
    mask = rope_mask(rgb, x0)
    fixed = cv2.cvtColor(cv2.inpaint(cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR), mask, 6, cv2.INPAINT_TELEA), cv2.COLOR_BGR2RGB)
    out = Image.fromarray(fixed).convert("RGBA")
    out.putalpha(Image.fromarray(mask).filter(ImageFilter.GaussianBlur(1.2)))
    return out


def main() -> int:
    check = "--check" in sys.argv
    bad = 0
    for name, layers, x0 in (("state_stopper_empty_day.png", ["fg_pier_edge", "fg_water"], 680),
                             ("state_stopper_empty_dusk.png", ["fg_pier_edge", "fg_water", "dusk"], 820)):
        im = patch(layers, x0)
        target = R1 / name
        if check:
            same = target.exists() and ImageChops.difference(Image.open(target).convert("RGBA"), im).getbbox() is None
            print(f"{'OK  ' if same else 'DIFF'} {target.relative_to(ROOT)}")
            bad += 0 if same else 1
        else:
            im.save(target, optimize=True)
            print(f"wrote {target.relative_to(ROOT)} {im.size[0]}x{im.size[1]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
