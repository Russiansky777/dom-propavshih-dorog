#!/usr/bin/env python3
"""Слои H1, построенные из готового арта по геометрии фона (замечания Директора 18.10 по H1).

  state_shelf_stove.png — полка Тихона «в углу у печи» (Q04 A): рисунок ChatGPT
      assets/incoming/H1_state_shelf_stove.png был фронтальным и «торчал в комнату» (Директор: «полка идёт
      длинной в комнату, а не вдоль печи … широкой частью прилегать к печи»). Здесь он перекладывается
      перспективным преобразованием (cv2.warpPerspective) на боковую грань печи, обращённую к окну:
      длинная задняя кромка — вдоль грани, ближний к зрителю конец больше дальнего. Плюс мягкая тень на
      побелке, кочерги у угла печи остаются перед полкой (вырез по тёмному железу фона).
  state_holes_stove.png — гнёзда креплений на боковой грани там, где встанет полка A (видны, пока её нет),
      и едва заметный след снятых опор (побелку обновляли вокруг них: «вещи помнят место»);
  state_shelf_table.png — полка B «у стола» (Q04 B). Рисунок ChatGPT assets/incoming/H1_state_shelf_table.png
      висел на челе печи над дверцей, а по сценарию Q04 хвост Тихона не должен быть у горячей дверцы
      (координатор 18.10). Полка перенесена на заднюю стену слева от двери на крыльцо — под угловые полки с
      кувшинами, над кадкой, в кадре прямо над столиком; стена фронтальна, поэтому преобразование —
      масштаб по глубине стены (210,6 px/м у пола y 590) и мягкая тень влево-вниз (свет из окна справа);
  state_holes_table.png — два гнезда и след опор под полку B на той же стене (видны, пока её нет);
  fg_chair_arm.png      — ближний подлокотник кресла (вырез из fg_table_chair.png, тот же холст): рисуется
      над Тихоном, когда он сидит в кресле (порядок: кресло z 950 < Тихон < подлокотник).

Геометрия боковой грани (координаты фона 1672x941): горизонт y 371 (rooms/H1.json _depth_note: 426 на
экране), точка схода линий в глубину VP = (1520, 371) — по карнизу боковой грани (верх 205→230, низ
245→262 на x 330→500); передний угол печи x 322; 278 px/м у переднего угла (лавка: 0,47 м = 150 px
экрана у y 765 → 130,6 px фона); камера 1,04 м над полом; передний угол на расстоянии ZF = 6 м
(видимая часть грани до лежанки ≈ 1 м глубины). Точка грани на глубине d (м от угла), высоте h (м):
x = VP.x − (VP.x − 322)/k, y = 371 + (1.04 − h)·278/k, k = 1 + d/ZF.

Запуск: python3 tools/make_h1_layers.py          — записать слои в game/assets/rooms/H1/
        python3 tools/make_h1_layers.py --check  — сверить файлы с тем, что дал бы запуск (код 1 — расходятся)
        python3 tools/make_h1_layers.py --geometry — напечатать экранные точки (для rooms/H1.json, tikhon.json)
Нужны Pillow, numpy, opencv (не в CI: результат лежит в репозитории).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "assets" / "rooms" / "H1"
SRC_SHELF = ROOT / "assets" / "incoming" / "H1_state_shelf_stove.png"
SRC_SHELF_B = ROOT / "assets" / "incoming" / "H1_state_shelf_table.png"
BG = ROOT / "game" / "assets" / "rooms" / "H1" / "bg.png"
CHAIR = ROOT / "game" / "assets" / "rooms" / "H1" / "fg_table_chair.png"

W, H = 1672, 941
ART = 1920.0 / W            # фон → экран
VP = (1520.0, 371.0)        # точка схода глубины на горизонте
X_CORNER = 322.0            # передний вертикальный угол печи (начало боковой грани)
PX_M = 278.0                # px фона на метр у переднего угла
CAM_H = 1.04                # высота камеры, м
ZF = 6.0                    # расстояние до переднего угла, м

# Полка A на боковой грани: от d0 до d0 + L по глубине, верх доски на высоте TOP_H.
SHELF_D0 = 0.20
SHELF_L = 0.77
SHELF_TOP_H = 0.78
# Исходный рисунок: верхняя передняя кромка доски A(287,432) → B(790,452) (холст 1672x941); рисунок
# зеркалится, чтобы больший (ближний) кронштейн оказался у ближнего к зрителю конца.
SRC_A = (287.0, 432.0)
SRC_B = (790.0, 452.0)
SRC_TOP, SRC_BOT = -80.0, 140.0   # поля исходного четырёхугольника над/под кромкой, px

# Гнёзда A: на стене под кронштейнами, (глубина d, высота h) в метрах.
HOLES_A = [(0.27, 0.70), (0.27, 0.63), (0.88, 0.70)]
# Полка B «у стола» (координатор 18.10: по сценарию Q04 хвост не у горячей дверцы, а рисунок ChatGPT висел над
# ней на челе печи): задняя стена слева от двери на крыльцо, под угловыми полками с кувшинами, над кадкой —
# в кадре прямо над столиком. Стена фронтальна (параллельна кадру): перспектива сводится к масштабу по
# глубине стены — пол у стены y 590 (низ двери), 210,6 px фона/м (камера 1,04 м). Свободный участок
# побелки x 637–716 (левее — лежанка, правее — косяк двери), низ кронштейнов выше кадки (y 460).
BACK_FLOOR_Y = 590.0
PX_M_BACK = (BACK_FLOOR_Y - 371.0) / CAM_H
B_X0, B_X1 = 637.0, 716.0           # концы доски, px фона
B_TOP_H = 0.75                      # верх доски над полом, м
# Исходный рисунок B: доска x 47–333, верхняя кромка y 294 (холст 1672x941, по альфе).
SRC_B_A = (47.0, 294.0)
SRC_B_B = (333.0, 294.0)
SRC_B_TOP, SRC_B_BOT = -40.0, 100.0
# Гнёзда B — на полосах кронштейнов у стены (x по прямой кромке кронштейна), чуть ниже доски.
HOLES_B = [(644.0, 444.0), (703.0, 444.0)]
# Кочерги у угла печи (железо темнее LUM_IRON) — перед полкой.
POKER_BOX = (325, 400, 385, 520)
LUM_IRON = 72

# Подлокотник кресла — многоугольник в координатах холста fg_table_chair.png (1672x941; слой рисуется
# scale 0.6 × art 1.1483 с offset [200, 420] — rooms/H1.json).
ARM_POLY = [(50, 526), (200, 533), (300, 546), (324, 555), (334, 575), (327, 598), (307, 606), (318, 700),
            (327, 924), (298, 930), (254, 928), (244, 700), (238, 604), (58, 574), (46, 550)]


def k_of(d: float) -> float:
    return 1.0 + d / ZF


def wall_xy(d: float, h: float, off: float = 0.0) -> tuple[float, float]:
    """Точка на боковой грани печи (off — отступ от грани в комнату, м)."""
    k = k_of(d)
    return VP[0] - (VP[0] - X_CORNER) / k + off * PX_M / k, VP[1] + (CAM_H - h) * PX_M / k


def screen(p: tuple[float, float]) -> list[float]:
    return [round(p[0] * ART, 1), round(p[1] * ART, 1)]


def shelf_transform():
    import cv2
    a, b = np.array(SRC_A), np.array(SRC_B)
    px_m = float(np.linalg.norm(b - a)) / SHELF_L
    # зеркальный рисунок: кромка от (W-1-B.x) до (W-1-A.x)
    ma, mb = (W - 1 - b[0], b[1]), (W - 1 - a[0], a[1])
    s = np.float32([[ma[0], ma[1] + SRC_TOP], [mb[0], mb[1] + SRC_TOP], [mb[0], mb[1] + SRC_BOT], [ma[0], ma[1] + SRC_BOT]])
    ht = SHELF_TOP_H - SRC_TOP / px_m
    hb = SHELF_TOP_H - SRC_BOT / px_m
    d0, d1 = SHELF_D0, SHELF_D0 + SHELF_L
    t = np.float32([wall_xy(d0, ht), wall_xy(d1, ht), wall_xy(d1, hb), wall_xy(d0, hb)])
    return cv2.getPerspectiveTransform(s, t), px_m


def warp_rgba(img: np.ndarray, m) -> np.ndarray:
    """Перспектива с премультипликацией (чистые края альфы)."""
    import cv2
    f = img.astype(np.float32)
    pm = np.dstack([f[..., :3] * f[..., 3:4] / 255.0, f[..., 3:4]])
    out = cv2.warpPerspective(pm, m, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    a = out[..., 3:4]
    rgb = np.where(a > 0.5, out[..., :3] * 255.0 / np.maximum(a, 1e-3), 0)
    return np.dstack([rgb, a]).clip(0, 255).astype(np.uint8)


def build_shelf() -> Image.Image:
    src = np.array(Image.open(SRC_SHELF).convert("RGBA"))[:, ::-1].copy()
    # мусор генератора с почти нулевой альфой по всему холсту — убрать до преобразования
    src[src[..., 3] < 24] = 0
    m, _ = shelf_transform()
    shelf = Image.fromarray(warp_rgba(src, m), "RGBA")
    alpha = shelf.getchannel("A")
    # Тень на побелке: свет из окна справа почти по нормали к грани — тень прямо под полкой, чуть вниз.
    sh_a = ImageChops.offset(alpha, -2, 5).filter(ImageFilter.GaussianBlur(5)).point(lambda v: int(v * 0.42))
    shadow = Image.merge("RGBA", (*Image.new("RGB", (W, H), (58, 40, 26)).split(), sh_a))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(shadow)
    out.alpha_composite(shelf)
    # Кочерги перед полкой: обнулить слой там, где на фоне тёмное железо.
    bg = np.array(Image.open(BG).convert("RGB")).astype(np.float32)
    lum = bg @ np.array([0.299, 0.587, 0.114], np.float32)
    x0, y0, x1, y1 = POKER_BOX
    iron = np.zeros((H, W), np.uint8)
    iron[y0:y1, x0:x1] = (lum[y0:y1, x0:x1] < LUM_IRON).astype(np.uint8) * 255
    iron_m = Image.fromarray(iron, "L").filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    keep = ImageChops.invert(iron_m)
    out.putalpha(ImageChops.multiply(out.getchannel("A"), keep))
    return out


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


def build_holes_a() -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # следы опор: полосы на грани под кронштейнами (глубина ± 2 см, от доски до низа кронштейна) и
    # линия задней кромки доски
    for d in (HOLES_A[0][0], HOLES_A[2][0]):
        ghost(img, [wall_xy(d - 0.025, 0.745), wall_xy(d + 0.025, 0.745), wall_xy(d + 0.025, 0.585), wall_xy(d - 0.025, 0.585)], 1.0)
    d0, d1 = SHELF_D0 + 0.02, SHELF_D0 + SHELF_L - 0.02
    ghost(img, [wall_xy(d0, 0.765), wall_xy(d1, 0.765), wall_xy(d1, 0.75), wall_xy(d0, 0.75)], 0.8)
    for i, (d, h) in enumerate(HOLES_A):
        x, y = wall_xy(d, h)
        r = 0.022 * PX_M / k_of(d)               # ≈ 2,2 см (гнездо под деревянный нагель)
        socket(img, x, y, r * 0.62, r, 1.0, 11 + i)   # на грани в глубину круг сжат по горизонтали
    return img


def back_y(h: float) -> float:
    """y на задней стене (фронтальной) для высоты h м над полом."""
    return 371.0 + (CAM_H - h) * PX_M_BACK


def shelf_b_transform():
    import cv2
    s_len = SRC_B_B[0] - SRC_B_A[0]
    k = (B_X1 - B_X0) / s_len                       # px фона на px рисунка
    s = np.float32([[SRC_B_A[0], SRC_B_A[1] + SRC_B_TOP], [SRC_B_B[0], SRC_B_B[1] + SRC_B_TOP],
                    [SRC_B_B[0], SRC_B_B[1] + SRC_B_BOT], [SRC_B_A[0], SRC_B_A[1] + SRC_B_BOT]])
    y0 = back_y(B_TOP_H)
    t = np.float32([[B_X0, y0 + SRC_B_TOP * k], [B_X1, y0 + SRC_B_TOP * k],
                    [B_X1, y0 + SRC_B_BOT * k], [B_X0, y0 + SRC_B_BOT * k]])
    return cv2.getPerspectiveTransform(s, t), k


def build_shelf_b() -> Image.Image:
    src = np.array(Image.open(SRC_SHELF_B).convert("RGBA"))
    src[src[..., 3] < 24] = 0
    m, _ = shelf_b_transform()
    shelf = Image.fromarray(warp_rgba(src, m), "RGBA")
    alpha = shelf.getchannel("A")
    # Тень на стене: свет из окна справа скользит по задней стене — тень влево и вниз, мягкая.
    sh_a = ImageChops.offset(alpha, -3, 4).filter(ImageFilter.GaussianBlur(3.5)).point(lambda v: int(v * 0.45))
    shadow = Image.merge("RGBA", (*Image.new("RGB", (W, H), (40, 28, 18)).split(), sh_a))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(shadow)
    out.alpha_composite(shelf)
    return out


def build_holes_b() -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    k = (B_X1 - B_X0) / (SRC_B_B[0] - SRC_B_A[0])
    y_plank = back_y(B_TOP_H) + 20.0 * k
    y_low = back_y(B_TOP_H) + 92.0 * k
    for x, _y in HOLES_B:
        ghost(img, [(x - 4, y_plank), (x + 4, y_plank), (x + 4, y_low), (x - 4, y_low)], 0.8)
    ghost(img, [(B_X0 + 2, back_y(B_TOP_H) - 1), (B_X1 - 2, back_y(B_TOP_H) - 1), (B_X1 - 2, back_y(B_TOP_H) + 3), (B_X0 + 2, back_y(B_TOP_H) + 3)], 0.6)
    r = 0.02 * PX_M_BACK
    for i, (x, y) in enumerate(HOLES_B):
        socket(img, x, y, r * 0.9, r, 0.6, 51 + i)
    return img


def build_chair_arm() -> Image.Image:
    ch = Image.open(CHAIR).convert("RGBA")
    mask = Image.new("L", ch.size, 0)
    ImageDraw.Draw(mask).polygon(ARM_POLY, fill=255)
    out = ch.copy()
    out.putalpha(ImageChops.multiply(ch.getchannel("A"), mask))
    return out


def outputs() -> dict[str, Image.Image]:
    return {
        "state_shelf_stove.png": build_shelf(),
        "state_holes_stove.png": build_holes_a(),
        "state_shelf_table.png": build_shelf_b(),
        "state_holes_table.png": build_holes_b(),
        "fg_chair_arm.png": build_chair_arm(),
    }


def geometry() -> dict:
    """Экранные точки (1920x1080) полки A и гнёзд — для данных комнаты и куклы."""
    d0, d1 = SHELF_D0, SHELF_D0 + SHELF_L
    return {
        "shelf_a_top_wall_near": screen(wall_xy(d0, SHELF_TOP_H)),
        "shelf_a_top_wall_far": screen(wall_xy(d1, SHELF_TOP_H)),
        "shelf_a_top_mid_front": screen(wall_xy((d0 + d1) / 2, SHELF_TOP_H, 0.12)),
        "shelf_a_floor_mid": screen(wall_xy((d0 + d1) / 2, 0.0, 0.12)),
        "holes_a": [screen(wall_xy(d, h)) for d, h in HOLES_A],
        "shelf_b_top_left": screen((B_X0, back_y(B_TOP_H))),
        "shelf_b_top_right": screen((B_X1, back_y(B_TOP_H))),
        "shelf_b_floor_y": round(BACK_FLOOR_Y * ART, 1),
        "holes_b": [screen(p) for p in HOLES_B],
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
