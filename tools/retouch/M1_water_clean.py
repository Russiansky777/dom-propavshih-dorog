"""Вода у колеса мельницы без нарисованной пены и брызг (Директор 02.11, стр. 1: «вода на мельнице — всё ещё не ок…
нижняя часть статичная, и брызги статичны и нарисованы, что нереально»): слой water_1 (вода перед колесом) собирается
заново из фона, заплаты лотка и прежнего слоя (холст 1672×941, assets/incoming/M1_bg.png, M1_state_wheel_pit.png),
и на нём светлые пятна пены и столб брызг (яркость выше медианы окрестности на LIFT, насыщенность ниже SAT_MAX,
чуть расширенные) заменяются той же строкой чистой воды ниже по течению (справа от колеса, x ≥ 1430 холста — там
пены не рисовали; рябь горизонтальная, повтор по строке не виден), с мягким краем. Прозрачность — прежняя (форма воды слоя). Пена, брызги и струи — только живые:
шейдер воды (ambient/M1.json water wheel_foam) и частицы колеса (wheel_water: ковши, удар лопастей, пена кружевом)."""
from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LIFT = 20
SAT_MAX = 75
WATER_Y = (520, 700)
CLEAN_X0 = 1330   # the race's clean water under the gate (bg + pit, without this layer): x 1330–1490 of the canvas
PERIOD = 160


def retouch(im: Image.Image) -> Image.Image:
    layer = np.array(im.convert("RGBA"))
    al = layer[..., 3]
    comp = Image.open(ROOT / "assets/incoming/M1_bg.png").convert("RGBA")
    comp.alpha_composite(Image.open(ROOT / "assets/incoming/M1_state_wheel_pit.png").convert("RGBA"))
    base = np.array(comp)[..., :3].copy()   # fill source: the race without this layer's painted foam
    comp.alpha_composite(im.convert("RGBA"))
    c = np.array(comp)[..., :3]
    hsv = cv2.cvtColor(c, cv2.COLOR_RGB2HSV)
    v = hsv[..., 2].astype(np.int32)
    s = hsv[..., 1].astype(np.int32)
    med = cv2.medianBlur(hsv[..., 2], 41).astype(np.int32)
    band = np.zeros(al.shape, bool)
    band[WATER_Y[0]:WATER_Y[1], :] = True
    water = band & (al > 0)
    foam = water & (v > med + LIFT) & (s < SAT_MAX)
    # also the plume's bright tips above the water line and the light swirl right under the wheel
    foam |= water & (v > 150) & (s < 40)
    foam = cv2.dilate(foam.astype(np.uint8), np.ones((5, 5), np.uint8), iterations=3) > 0
    foam &= water
    # a source pixel must be water itself: grey-blue, not the bank's yellow grass and clay inside the layer
    hue = hsv[..., 0].astype(np.int32)
    watery = water & ~foam & ((s < 45) | ((hue > 80) & (hue < 130))) & (v < med - 4)
    # the fill: the same row's clean water downstream of the race (right of the wheel, x ≥ CLEAN_X0 — no foam
    # was painted there), tiled along the row with a gentle cross-fade; rows without clean water take the nearest row's
    bh = cv2.cvtColor(base, cv2.COLOR_RGB2HSV).astype(np.int32)
    src_ok = band & ~((bh[..., 0] >= 5) & (bh[..., 0] <= 35) & (bh[..., 1] > 70)) & (bh[..., 2] < 150)   # not grass
    # the fill: the water's own colour round the foam (inpaint at half size — a smooth field, no copied patterns), with
    # a fifth of the old picture's ripple left in it; the live foam and streaks come from the shader and the particles
    small = cv2.resize(c, (c.shape[1] // 2, c.shape[0] // 2), interpolation=cv2.INTER_AREA)
    m_small = cv2.resize(foam.astype(np.uint8) * 255, (c.shape[1] // 2, c.shape[0] // 2), interpolation=cv2.INTER_NEAREST)
    smooth = cv2.resize(cv2.inpaint(small, m_small, 9, cv2.INPAINT_TELEA), (c.shape[1], c.shape[0]), interpolation=cv2.INTER_CUBIC)
    detail = c.astype(np.float32) - cv2.GaussianBlur(c, (0, 0), 2.0).astype(np.float32)
    fill = np.clip(smooth.astype(np.float32) + detail * 0.25, 0, 255).astype(np.uint8)
    soft = cv2.GaussianBlur(foam.astype(np.float32), (0, 0), 3.0)[..., None]
    out = (c * (1 - soft) + fill * soft).astype(np.uint8)
    res = np.dstack([out, al])
    return Image.fromarray(res, "RGBA")
