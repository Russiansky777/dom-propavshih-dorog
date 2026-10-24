#!/usr/bin/env python3
"""H36 / T8 (Директор 24.10): после скобы (M15s) лодка Пелагеи стоит у поворота — привязана у плиты, под канатом;
причал R1 с этой минуты без лодки. Пока нет арта партии 10в — временные слои из уже нарисованной лодки:

  game/assets/rooms/R1/state_no_boat_dusk.png       — заплатка без лодки поверх вечера дня второго
                                                      (bg + fg_pier_edge + fg_water + dusk);
  game/assets/rooms/R1/state_no_boat_day.png        — то же днём дней 3–4 (state_water_low_day);
  game/assets/rooms/R1/state_no_boat_d3_evening.png — вечер третьего дня (state_water_low_day + dusk);
  game/assets/rooms/Z3/state_boat.png               — та же лодка у плиты на опоре в воде у поворота: вырезана по
      контуру из дневного кадра R1 (state_water_low_day), нос к плите, уменьшена по перспективе Z3, с
      бледным отражением в воде; в сумерках слой тонируется в данных (rooms/Z3.json → modulate).

Заплатка R1: лодка, её отражение и швартов до столба — заливка водой из полосы над лодкой (растянута по глубине),
низкие частоты — гладкая поверхность по чистой воде вокруг (берег и столбы исключены). Холст 1672×941 (как фон).

Запуск: python3 tools/make_boat_layers.py           — записать слои
        python3 tools/make_boat_layers.py --check   — сверить с репозиторием (код 1 — расходятся)
Нужны Pillow, numpy, opencv (не в CI: результат в репозитории).
"""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parent.parent
R1 = ROOT / "game" / "assets" / "rooms" / "R1"
Z3 = ROOT / "game" / "assets" / "rooms" / "Z3"
W, H = 1672, 941
O = (1250, 420)  # начало координат контуров ниже — пиксели фона R1
BOAT = [(112, 74), (126, 58), (142, 58), (150, 66), (200, 74), (260, 88), (330, 102), (392, 106), (410, 116),
        (412, 130), (398, 150), (384, 190), (372, 200), (330, 195), (250, 183), (180, 168), (140, 152), (120, 133),
        (110, 108)]
ROPE = [(64, 60), (110, 84), (150, 122), (196, 108), (198, 165), (140, 165), (80, 125), (64, 90)]
REFL = {"dusk": [(118, 140), (422, 120), (422, 292), (280, 266), (130, 200)],
        "day": [(118, 140), (422, 120), (422, 330), (230, 300), (130, 215)]}
WATER_BAND = (396, 466)  # полоса чистой воды над лодкой (строки фона R1)
# Z3: лодка носом к опоре с плитой (кольцо — 1112, 503 холста), на мелкой воде перед опорами слева от неё, под
# канатом, что уходит от кольца к тому берегу; масштаб — по камням опор (камень ≈ 55 px ≈ 1 м, лодка ≈ 3 м)
Z3_SCALE = 0.52
Z3_AT = (940, 471)        # левый верх вырезанной лодки на холсте Z3 (экран ≈ 1080, 541)


def compose(names: list[str]) -> Image.Image:
    base = Image.open(R1 / "bg.png").convert("RGBA")
    for n in names:
        base.alpha_composite(Image.open(R1 / f"{n}.png").convert("RGBA"))
    return base.convert("RGB")


def hole(kind: str) -> np.ndarray:
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    for p in (BOAT, REFL[kind], ROPE):
        d.polygon([(x + O[0], y + O[1]) for x, y in p], fill=255)
    a = np.array(m.filter(ImageFilter.MaxFilter(9)))
    edge = a[:, 1650:1652].max(1, keepdims=True) > 0   # корма у края кадра — до края
    a[:, 1662:] = np.where(edge, 255, a[:, 1662:])
    a[:, :1350] = 0   # столбы причала со своим мотком — не трогать (обрывок швартова у мотка остаётся)
    return a


def no_boat(img: Image.Image, kind: str) -> Image.Image:
    src = np.array(img)
    m = hole(kind)
    ys, _ = np.nonzero(m)
    y0, y1 = int(ys.min()), int(ys.max())
    out = src.copy()
    top, bot = WATER_BAND
    for y in range(y0, y1 + 1):
        row = m[y] > 0
        out[y, row] = src[top + (bot - top) * ((y - y0) % 60) // 60, row]
    # Низкие частоты — гладкая поверхность (полином 2-й степени по x, y) по чистой воде вокруг: без столбов причала
    # слева, берега внизу и самой лодки; так в заплатке нет полос и пятен от краёв.
    yy, xx = np.mgrid[0:H, 0:W]
    near = cv2.dilate(m, np.ones((121, 121), np.uint8)) > 0
    water = near & (m == 0) & (xx > 1352) & (yy > WATER_BAND[0]) & ~((yy > 640 + (xx - 1330) * 0.35) & (xx > 1300))
    blur = cv2.GaussianBlur(src.astype(float), (0, 0), 5)
    def basis(x, y):
        x = (x - 1500.0) / 200.0
        y = (y - 560.0) / 150.0
        return np.stack([np.ones_like(x), x, y, x * x, x * y, y * y], -1)
    A = basis(xx[water].astype(float), yy[water].astype(float))
    hy, hx = np.nonzero(m)
    low = blur.copy()
    for c in range(3):
        coef, *_ = np.linalg.lstsq(A, blur[..., c][water], rcond=None)
        low[hy, hx, c] = basis(hx.astype(float), hy.astype(float)) @ coef
    tex = (out.astype(float) - cv2.GaussianBlur(out.astype(float), (0, 0), 5)) * 0.7
    filled = np.clip(tex + low, 0, 255).astype(np.uint8)
    alpha = np.array(Image.fromarray(m).filter(ImageFilter.GaussianBlur(4)))
    return Image.fromarray(np.dstack([filled, alpha]), "RGBA")


def boat_sprite() -> Image.Image:
    src = Image.open(R1 / "state_water_low_day.png").convert("RGB")
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon([(x + O[0], y + O[1]) for x, y in BOAT], fill=255)
    rgba = src.copy()
    rgba.putalpha(m.filter(ImageFilter.GaussianBlur(1.2)))
    box = (O[0] + 104, O[1] + 52, O[0] + 418, O[1] + 206)
    boat = rgba.crop(box)
    w, h = boat.size
    return boat.resize((round(w * Z3_SCALE), round(h * Z3_SCALE)), Image.LANCZOS)


def z3_boat() -> Image.Image:
    boat = boat_sprite()
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    refl = ImageOps.flip(boat)
    r, g, b, a = refl.split()
    dark = Image.merge("RGB", (r, g, b)).point(lambda v: int(v * 0.55))
    fade = Image.linear_gradient("L").resize(refl.size)            # сверху ярче, вниз гаснет
    fade = ImageOps.invert(fade).point(lambda v: int(v * 0.32))
    a = Image.fromarray((np.array(a, float) * np.array(fade, float) / 255).astype(np.uint8))
    refl = Image.merge("RGBA", (*dark.split(), a)).filter(ImageFilter.GaussianBlur(1.5))
    waterline = Z3_AT[1] + int(boat.size[1] * 0.93)
    canvas.alpha_composite(refl, (Z3_AT[0], waterline - int(boat.size[1] * 0.07)))
    canvas.alpha_composite(boat, Z3_AT)
    return canvas


def build() -> dict[Path, Image.Image]:
    return {
        R1 / "state_no_boat_dusk.png": no_boat(compose(["fg_pier_edge", "fg_water", "dusk"]), "dusk"),
        R1 / "state_no_boat_day.png": no_boat(compose(["fg_pier_edge", "fg_water", "state_water_low_day"]), "day"),
        R1 / "state_no_boat_d3_evening.png": no_boat(compose(["fg_pier_edge", "fg_water", "state_water_low_day", "dusk"]), "dusk"),
        Z3 / "state_boat.png": z3_boat(),
    }


def main() -> int:
    out = build()
    if "--check" in sys.argv:
        bad = 0
        for p, im in out.items():
            if not p.exists() or np.abs(np.array(Image.open(p).convert("RGBA"), int) - np.array(im, int)).max() > 2:
                print(f"[boat] расходится: {p.relative_to(ROOT)}")
                bad += 1
        return 1 if bad else 0
    for p, im in out.items():
        im.save(p, optimize=True)
        print(f"[boat] {p.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
