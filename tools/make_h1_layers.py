#!/usr/bin/env python3
"""Слои H1, построенные из готового арта по геометрии фона (замечания Директора 18.10 и 23.10 по H1).

  state_holes_stove.png — гнёзда креплений на стене там, где встанет полка A (видны, пока её нет), и едва заметный
      след снятых кронштейнов («вещи помнят место»); state_holes_table.png — то же для полки B у двери на крыльцо.
      Партия G (G12, арт партии 9): полки A и B — один рисунок ChatGPT (доска 92 px фона, H1_state_shelf_A/_B,
      импорт tools/import_room_art.py H1), гнёзда стоят под их кронштейнами: кронштейны замерены по альфе
      этих слоёв (BRACKETS_A/_B ниже) — когда полка повешена, кронштейн закрывает свои гнёзда.
      Прежние полки этого инструмента (перспектива рисунков партии 1 на грань печи и на заднюю стену) сняты
      вместе с ними: в игре одна полка из партии 9.
  fg_chair_arm.png      — ближний подлокотник кресла (вырез из fg_table_chair.png, тот же холст): рисуется
      над Тихоном, когда он сидит в кресле (порядок: кресло z 950 < Тихон < подлокотник).

Запуск: python3 tools/make_h1_layers.py          — записать слои в game/assets/rooms/H1/
        python3 tools/make_h1_layers.py --check  — сверить файлы с тем, что дал бы запуск (код 1 — расходятся)
        python3 tools/make_h1_layers.py --geometry — напечатать экранные точки (для rooms/H1.json, tikhon.json)
Нужны Pillow и numpy (не в CI: результат лежит в репозитории).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "assets" / "rooms" / "H1"
CHAIR = ROOT / "game" / "assets" / "rooms" / "H1" / "fg_table_chair.png"

W, H = 1672, 941
ART = 1920.0 / W            # фон → экран

# Кронштейны полок партии 9 (координаты фона 1672×941, замер по альфе state_shelf_A/_B.png: под доской — два
# столбца непрозрачных пикселей): (x0, x1) каждого кронштейна и общий y от низа доски до носка кронштейна.
BRACKETS_A = [(393.0, 401.0), (449.0, 458.0)]
BRACKETS_A_Y = (456.0, 489.0)
BOARD_A = (382.0, 467.0, 452.0)     # доска A: x от, x до, нижняя кромка у стены
BRACKETS_B = [(634.0, 644.0), (692.0, 700.0)]
BRACKETS_B_Y = (444.0, 471.0)
BOARD_B = (625.0, 710.0, 441.0)
# Гнёзда — на полосе кронштейна у стены: у A по два на левом и одно на правом (как было), у B по одному.
HOLES_A = [(397.0, 466.0), (397.0, 480.0), (453.5, 466.0)]
HOLES_B = [(639.0, 455.0), (696.0, 455.0)]
R_A, R_B = 3.6, 3.4                 # радиус гнезда, px фона (≈ 2 см под нагель; гнездо уже кронштейна — тот его закрывает)

# Подлокотник кресла — многоугольник в координатах холста fg_table_chair.png (1672x941; слой рисуется
# scale 0.6 × art 1.1483 с offset [200, 420] — rooms/H1.json).
ARM_POLY = [(50, 526), (200, 533), (300, 546), (324, 555), (334, 575), (327, 598), (307, 606), (318, 700),
            (327, 924), (298, 930), (254, 928), (244, 700), (238, 604), (58, 574), (46, 550)]


def _blob(cx: float, cy: float, rx: float, ry: float, rng: np.random.Generator, n: int = 28, jitter: float = 0.16):
    """Неровный овал (сколотая кромка гнезда): радиус с шумом, сглаженным по кругу."""
    t = np.linspace(0, 2 * np.pi, n, endpoint=False)
    r = 1.0 + rng.normal(0, jitter, n)
    r = (r + np.roll(r, 1) + np.roll(r, -1)) / 3.0
    return [(cx + rx * r[i] * np.cos(t[i]), cy + ry * r[i] * np.sin(t[i])) for i in range(n)]


def socket(img: Image.Image, cx: float, cy: float, rx: float, ry: float, lit: float, seed: int) -> None:
    """Гнездо от выдернутого крепления в старой побелке: неровная тёмная дырка (правая внутренняя стенка
    в тени — свет из окна справа), светлый скол кромки справа, потёртый ореол. lit — яркость грани."""
    rng = np.random.default_rng(seed)
    s = 8  # суперсэмплинг
    box = (int(cx - rx * 4) - 2, int(cy - ry * 4) - 2, int(cx + rx * 4) + 3, int(cy + ry * 4) + 3)
    bw, bh = box[2] - box[0], box[3] - box[1]
    ox, oy = (cx - box[0]) * s, (cy - box[1]) * s
    big = Image.new("RGBA", (bw * s, bh * s), (0, 0, 0, 0))

    def layer(poly, rgb, alpha, blur):
        m = Image.new("L", big.size, 0)
        ImageDraw.Draw(m).polygon(poly, fill=alpha)
        if blur > 0:
            m = m.filter(ImageFilter.GaussianBlur(blur * s))
        big.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", big.size, rgb).split(), m)))

    # потёртость вокруг (пыль и сколы побелки), чуть смещена вниз
    layer(_blob(ox, oy + ry * 0.5 * s, rx * 2.2 * s, ry * 2.2 * s, rng, jitter=0.22), (112, 88, 64), int(58 * lit), rx * 0.9)
    # светлый скол кромки справа (освещённый край) — узкий серп
    layer(_blob(ox + rx * 0.55 * s, oy - ry * 0.1 * s, rx * 1.1 * s, ry * 1.2 * s, rng), (246, 236, 220), int(52 * lit), 0.6)
    # тёмная кромка (тень скола)
    layer(_blob(ox - rx * 0.05 * s, oy + ry * 0.08 * s, rx * 1.15 * s, ry * 1.15 * s, rng), (98, 76, 56), 170, 0.6)
    # сама дырка: тёмная, к правой стенке темнее
    hole = Image.new("L", big.size, 0)
    ImageDraw.Draw(hole).polygon(_blob(ox, oy, rx * 0.92 * s, ry * 0.92 * s, rng, jitter=0.12), fill=245)
    hole = hole.filter(ImageFilter.GaussianBlur(0.35 * s))
    xs = np.linspace(0.0, 1.0, big.size[0], dtype=np.float32)[None, :].repeat(big.size[1], 0)
    shade = np.clip((xs - (ox - rx * s) / big.size[0]) / max(2 * rx * s / big.size[0], 1e-3), 0, 1)
    rgb = np.dstack([46 - 26 * shade, 34 - 20 * shade, 26 - 16 * shade]).clip(0, 255).astype(np.uint8)
    big.alpha_composite(Image.merge("RGBA", (*Image.fromarray(rgb, "RGB").split(), hole)))
    img.alpha_composite(big.resize((bw, bh), Image.LANCZOS), (box[0], box[1]))


def ghost(img: Image.Image, quad: list[tuple[float, float]], lit: float) -> None:
    """След снятой опоры: побелку обновляли вокруг неё — под ней полоса чуть темнее и без мазков
    («вещи помнят место»). Едва заметно, мягкий край."""
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon(quad, fill=int(44 * lit))
    m = m.filter(ImageFilter.GaussianBlur(1.6))
    img.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (W, H), (150, 124, 96)).split(), m)))


def _holes(brackets, y_span, board, holes, r, lit, seed0) -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    y0, y1 = y_span
    # следы кронштейнов: побелку обновляли вокруг них — полоса чуть темнее, от доски до носка кронштейна
    for x0, x1 in brackets:
        ghost(img, [(x0 + 1, y0), (x1 - 1, y0), (x1 - 2, y1 - 2), (x0 + 2, y1 - 2)], lit)
    bx0, bx1, by = board
    ghost(img, [(bx0, by - 2), (bx1, by - 2), (bx1, by + 2), (bx0, by + 2)], 0.7 * lit)
    for i, (x, y) in enumerate(holes):
        socket(img, x, y, r * 0.9, r, lit, seed0 + i)
    return img


def build_holes_a() -> Image.Image:
    return _holes(BRACKETS_A, BRACKETS_A_Y, BOARD_A, HOLES_A, R_A, 1.0, 11)


def build_holes_b() -> Image.Image:
    return _holes(BRACKETS_B, BRACKETS_B_Y, BOARD_B, HOLES_B, R_B, 0.7, 51)


def build_chair_arm() -> Image.Image:
    ch = Image.open(CHAIR).convert("RGBA")
    mask = Image.new("L", ch.size, 0)
    ImageDraw.Draw(mask).polygon(ARM_POLY, fill=255)
    out = ch.copy()
    out.putalpha(ImageChops.multiply(ch.getchannel("A"), mask))
    return out


def outputs() -> dict[str, Image.Image]:
    return {
        "state_holes_stove.png": build_holes_a(),
        "state_holes_table.png": build_holes_b(),
        "fg_chair_arm.png": build_chair_arm(),
    }


def screen(p: tuple[float, float]) -> list[float]:
    return [round(p[0] * ART, 1), round(p[1] * ART, 1)]


def geometry() -> dict:
    """Экранные точки (1920x1080) гнёзд и кронштейнов — для данных комнаты."""
    return {
        "holes_a": [screen(p) for p in HOLES_A],
        "holes_b": [screen(p) for p in HOLES_B],
        "brackets_a": [[screen((x0, BRACKETS_A_Y[0])), screen((x1, BRACKETS_A_Y[1]))] for x0, x1 in BRACKETS_A],
        "brackets_b": [[screen((x0, BRACKETS_B_Y[0])), screen((x1, BRACKETS_B_Y[1]))] for x0, x1 in BRACKETS_B],
    }


def main() -> int:
    if "--geometry" in sys.argv:
        print(json.dumps(geometry(), ensure_ascii=False, indent=1))
        return 0
    check = "--check" in sys.argv
    bad = 0
    for name, im in outputs().items():
        target = OUT / name
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
