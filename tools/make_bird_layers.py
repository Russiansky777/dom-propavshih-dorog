#!/usr/bin/env python3
"""Синица на плакате в классе (O1) — шапка, сапоги и шарф по месту (партия J, Директор 29.10, стр. 53: «шарф не видно,
шапка и ботинки не на идеальном месте — сверить место до введения в игру, показав мне»; 19:19: «синица получилась
намного лучше, разве что боты — чтобы закрывали пальцы птицы и в том же направлении, что и палочки лап, побольше»).

Из поставки партии 9 (assets/incoming/O1_state_bird_doodles_v2.png, O1_state_bird_add_scarf.png) пишет слои игры:
  game/assets/rooms/O1/state_bird_doodles.png  — шапка сдвинута на макушку (глаз открыт); каждый сапог — отдельно,
                                                 крупнее (×1,3), повёрнут вдоль своей лапки и надет на пальцы;
  game/assets/rooms/O1/state_bird_add_scarf.png — тот же шарф, но видимый: полоски красная / кремовая цветным
                                                 карандашом, плотнее, на 3 px выше (на шее).
Координаты — пиксели холста 1672×941 (как слои). Запуск из корня: python3 tools/make_bird_layers.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
INC = ROOT / "assets" / "incoming"
OUT = ROOT / "game" / "assets" / "rooms" / "O1"

HAT_SHIFT = (-9, -3)                        # на макушку: левее и выше
LEFT_BOOT = ((1355, 294), 1.3, 35)          # центр на пальцах левой лапки, масштаб, поворот (° против часовой — вдоль лапки)
RIGHT_BOOT = ((1372, 290), 1.3, 55)         # правая лапка обхватывает ветку
SCARF = {"gain": 1.8, "alpha_max": 205, "stripe_px": 3, "red": (150, 62, 52), "cream": (214, 202, 180), "lift_px": 3}


def _rgba(p: Path, size=None) -> np.ndarray:
    im = Image.open(p).convert("RGBA")
    if size and im.size != size:
        pad = Image.new("RGBA", size)
        pad.paste(im, (0, 0))
        im = pad
    return np.asarray(im).copy()


def _boot(a: np.ndarray, x0: int, x1: int) -> Image.Image:
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    m = (a[..., 3] > 25) & (yy >= 276) & (xx >= x0) & (xx < x1)
    ys, xs = np.where(m)
    sub = np.zeros_like(a)
    sub[m] = a[m]
    return Image.fromarray(sub).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def _place(canvas: Image.Image, spr: Image.Image, center, scale: float, angle: float) -> None:
    s = spr.resize((round(spr.width * scale), round(spr.height * scale)), Image.LANCZOS)
    s = s.rotate(angle, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(s, (round(center[0] - s.width / 2), round(center[1] - s.height / 2)))


def doodles() -> Image.Image:
    a = _rgba(INC / "O1_state_bird_doodles_v2.png")
    h, w = a.shape[:2]
    yy, _ = np.mgrid[0:h, 0:w]
    out = np.zeros_like(a)
    ys, xs = np.where((a[..., 3] > 0) & (yy < 240))
    out[ys + HAT_SHIFT[1], xs + HAT_SHIFT[0]] = a[ys, xs]
    canvas = Image.fromarray(out)
    _place(canvas, _boot(a, 0, 1350), *LEFT_BOOT)
    _place(canvas, _boot(a, 1350, 10000), *RIGHT_BOOT)
    return canvas


def scarf(size) -> Image.Image:
    sc = _rgba(INC / "O1_state_bird_add_scarf.png", size).astype(float)
    h, w = sc.shape[:2]
    _, xx = np.mgrid[0:h, 0:w]
    al = sc[..., 3]
    lum = (sc[..., 0] * 0.3 + sc[..., 1] * 0.59 + sc[..., 2] * 0.11) / 255.0
    stripe = (xx // SCARF["stripe_px"]) % 2 == 0
    col = np.where(stripe[..., None], np.array(SCARF["red"]), np.array(SCARF["cream"])).astype(float)
    out = np.zeros_like(sc)
    out[..., :3] = np.clip(col * (0.75 + 0.35 * lum)[..., None], 0, 255)
    out[..., 3] = np.clip(al * SCARF["gain"], 0, SCARF["alpha_max"])
    out[al <= 0] = 0
    out = np.roll(out, -SCARF["lift_px"], axis=0)
    return Image.fromarray(out.astype(np.uint8))


def main() -> int:
    d = doodles()
    d.save(OUT / "state_bird_doodles.png", optimize=True)
    scarf(d.size).save(OUT / "state_bird_add_scarf.png", optimize=True)
    print("wrote", OUT / "state_bird_doodles.png", OUT / "state_bird_add_scarf.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
