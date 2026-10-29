#!/usr/bin/env python3
"""Слои предметов и выборов E0–E1 (замечания Директора 18.10: «где будет стоять фотография — никакой выбор
ничего не меняет», «мел нужно положить на ученический стол, чтобы было видно»). Всё собирается кодом из
готового арта игры; оригиналы (assets/incoming, game/assets/rooms/*/bg.png, fg_*.png) не меняются.

H1 (V01 «Чашка на своём месте»):
  state_photo_ledge.png  — семейная фотография в рамке до выбора: стоит на уступе печи у стены, рядом с
      латунной фигуркой (свободное место уступа x 690–720 экрана). Рамка — код (дерево, паспарту), снимок —
      сепия с тремя фигурами-силуэтами из листа Агаты (idle, анфас) разного роста; лицо не читается.
  state_photo_table.png  — после «На столе»: стоит на столике у кресла за книгой (книга закрывает низ рамки;
      слой рисуется под столиком, z 940 < 950).
  state_photo_shelf.png  — после «На полке»: на средней полке угловой полки с кувшинами, перед шкатулкой
      (правее — стебли сухоцвета из вазы нижней полки, туда не ставим).
  state_cup_sill_blue.png / state_cup_sill_white.png — две чашки ждут на подоконнике между кувшином и
      книгами (каждая — пока её не выбрали).
  state_cup_table_blue.png / state_cup_table_white.png — выбранная чашка на правом конце столика (z 955,
      поверх столика).
  Чашки — кружка со столика (fg_table_chair.png, вырез по контуру) в другой глазури: синяя — кобальт,
  белая — фаянс; перекраска по яркости, крап приглушён. Масштаб по глубине: подоконник ≈ 2,4 px/см
  экрана, столик ≈ 4,8 px/см (кружка 9 см ≈ 43 px), уступ печи ≈ 2,6 px/см, угловая полка ≈ 1,7 px/см.
  Тени: контактная под донцем и мягкая на стену — влево (свет из окна справа), на подоконнике — к зрителю
  (окно за спиной у вещей). Тон каждой вещи подогнан к средней яркости места (окрестность на фоне).
O1:
  state_chalk_desk.png   — мел на левой ученической парте (переднего плана), на её столешнице, близко к
      проходу за партами, где стоит Агата; иконка assets/icons/chalk.png повёрнута почти вдоль парты,
      ракурс столешницы (сжатие по вертикали 0,6), масштаб парты ≈ 4 px/см (мел ≈ 11 см ≈ 44 px — заметен с обычного вида), тень.
      Рисуется поверх парт (z 1081), пока мел не взят.
  patch_teacher_chalk.png — заплатка учительского стола: мелки, нарисованные на столе в фоне, убраны
      (cv2.inpaint по маске из окрестной текстуры стола/стены), чтобы мел был один — на парте.
  state_bird_mark.png    — пометка Агаты карандашом на полях картинки с птицей (V03 «Оставить свою
      пометку»): короткая строчка от руки и подчёркивание, графит.

Запуск: python3 tools/make_items_layers.py            — записать слои
        python3 tools/make_items_layers.py --check    — сверить файлы с пересборкой (код 1 — расходятся)
        python3 tools/make_items_layers.py --preview DIR — кадры-сборки для глаза (фон + слои)
        python3 tools/make_items_layers.py --geometry — прямоугольники вещей на экране (для rooms/*.json)
Нужны Pillow, numpy, opencv (не в CI: результат лежит в репозитории).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ROOMS = ROOT / "game" / "assets" / "rooms"
H1_BG = ROOMS / "H1" / "bg.png"
H1_TABLE = ROOMS / "H1" / "fg_table_chair.png"
O1_BG = ROOMS / "O1" / "bg.png"
O1_DESKS = ROOMS / "O1" / "fg_desks.png"
AGATA_IDLE = ROOT / "game" / "assets" / "characters" / "agata" / "idle.png"
CHALK_ICON = ROOT / "assets" / "icons" / "chalk.png"

W, H = 1672, 941             # холст H1 (фон и слои)
OW, OH = 1672, 940           # холст O1
ART = 1920.0 / W             # фон → экран
TABLE_OFF = (200.0, 420.0)   # rooms/H1.json table_chair: offset, scale 0.6
TABLE_S = ART * 0.6

# Кружка на столике — контур в пикселях fg_table_chair.png (рука по крупному плану слоя).
MUG_BODY = [(789, 441), (790, 452), (791, 466), (794, 481), (798, 492), (804, 499), (812, 502), (822, 503),
            (834, 503), (843, 500), (849, 495), (852, 485), (853, 470), (853, 455), (853, 446), (850, 440),
            (840, 436), (822, 434), (803, 435), (792, 438)]
MUG_HANDLE = [(851, 450), (858, 446), (866, 446), (872, 451), (875, 459), (876, 468), (873, 477), (867, 484),
              (860, 488), (855, 491), (851, 492)]
MUG_HOLE = [(852, 459), (858, 455), (864, 457), (867, 464), (866, 472), (862, 479), (856, 484), (852, 485)]
MUG_BOX = (785, 430, 880, 506)
MUG_BODY_W = 853 - 789       # ширина тулова в px слоя (без ручки)
MUG_BASE = (821, 503)        # середина донца в px слоя

# Места (экран 1920x1080): середина низа вещи, ширина тулова/рамки в px экрана.
PLACES = {
    # фотография: (x середины низа, y низа, ширина рамки)
    "photo_ledge": (706.0, 499.0, 25.0),
    "photo_table": (679.0, 737.0, 46.0),
    "photo_shelf": (694.0, 322.0, 17.0),
    # чашки: (x середины донца, y донца, ширина тулова)
    "cup_sill_blue": (1598.0, 509.0, 21.0),
    "cup_sill_white": (1632.0, 509.0, 21.0),
    "cup_table": (823.0, 769.0, 35.0),
    # H15/H54 (Директор 24.10, арт партии 10а): чашки с блюдцем и кружка — (x середины донца, y донца, ширина
    # всей вещи с блюдцем / ручкой, px экрана). Крупнее прежних (21 / 35 px тулова); кружка — поверх нарисованной
    # на столике маленькой (её донце — MUG_BASE, вся она ≈ 65 px экрана — новая шире и выше, закрывает её целиком).
    "cup10_sill_blue": (1590.0, 512.0, 40.0),
    "cup10_sill_white": (1636.0, 512.0, 40.0),
    "cup10_table": (826.0, 769.0, 56.0),
    # H54/T6 (Директор 24.10: «кружка синяя очень маленькая»): 74 → 92 px; J (Директор 29.10, стр. 95: «большую
    # неподвижную — к размеру маленькой»): 92 → 66 px — вровень с выбранной чашкой (56 px × 1.18 в данных ≈ 66 px).
    # Нарисованная глиняная кружка столика из-под неё выглядывала бы — её больше нет: fg_table_chair_nomug.png.
    "mug10_table": (762.0, 767.0, 66.0),
    # мел на парте: (x середины, y середины, длина)
    "chalk_desk": (612.0, 784.0, 44.0),
}
PHOTO_ASPECT = 1.36          # высота/ширина рамки (10×13,6 см)


def to_bg(x: float, y: float) -> tuple[float, float]:
    return x / ART, y / ART


def lum(a: np.ndarray) -> np.ndarray:
    return 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


# --- кружка → чашки ----------------------------------------------------------------------------------------

def mug_cut() -> Image.Image:
    fg = Image.open(H1_TABLE).convert("RGBA")
    m = Image.new("L", fg.size, 0)
    d = ImageDraw.Draw(m)
    d.polygon(MUG_BODY, fill=255)
    d.polygon(MUG_HANDLE, fill=255)
    d.polygon(MUG_HOLE, fill=0)
    m = m.filter(ImageFilter.GaussianBlur(0.6))
    a = np.array(fg)
    a[:, :, 3] = (a[:, :, 3].astype(np.float32) * np.array(m, np.float32) / 255).astype(np.uint8)
    return Image.fromarray(a).crop(MUG_BOX)


def recolor(img: Image.Image, dark, mid, light, detail: float, gamma: float) -> Image.Image:
    arr = np.array(img).astype(np.float32) / 255
    al = arr[:, :, 3]
    L = lum(arr[:, :, :3])
    if detail < 1.0:
        ls = np.array(Image.fromarray((L * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2)), np.float32) / 255
        L = ls + (L - ls) * detail
    L = np.clip(L, 0, 1) ** gamma
    dark, mid, light = (np.array(c, np.float32) / 255 for c in (dark, mid, light))
    t = L[..., None]
    out = np.where(t < 0.5, dark + (mid - dark) * (t / 0.5), mid + (light - mid) * ((t - 0.5) / 0.5))
    return Image.fromarray(np.dstack([np.clip(out, 0, 1) * 255, al * 255]).astype(np.uint8), "RGBA")


def cups() -> dict[str, Image.Image]:
    m = mug_cut()
    return {
        "blue": recolor(m, (12, 22, 46), (46, 78, 140), (160, 188, 222), detail=0.55, gamma=1.35),
        "white": recolor(m, (96, 92, 88), (214, 210, 202), (252, 250, 245), detail=0.5, gamma=1.0),
    }


# --- семейная фотография --------------------------------------------------------------------------------

def figure_mask() -> np.ndarray:
    """Силуэт Агаты (idle, анфас, кадр 0) — основа фигур на старом снимке."""
    sheet = Image.open(AGATA_IDLE).convert("RGBA")
    fr = np.array(sheet.crop((0, 0, 288, 384)))[:, :, 3]
    ys, xs = np.where(fr > 60)
    return fr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def photo_master() -> Image.Image:
    """Рамка с паспарту и сепией 220×300 px (масштаб 1): уменьшается до места."""
    r = rng(18)
    w, h = 220, 300
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # дерево рамки
    wood = np.zeros((h, w, 3), np.float32)
    base = np.array([66, 40, 22], np.float32)
    grain = r.normal(0, 1, (h, 1)) * 6 + np.sin(np.linspace(0, 40, h))[:, None] * 4     # (h, 1)
    wood[:] = base[None, None, :] + (grain + r.normal(0, 4, (h, w)) * 0.6)[..., None]
    fr = Image.fromarray(np.clip(wood, 0, 255).astype(np.uint8))
    img.paste(fr, (0, 0))
    d = ImageDraw.Draw(img)
    b = 30                                   # ширина рамки (13 % — видна и в 17 px)
    d.rectangle([2, 2, w - 3, 5], fill=(128, 90, 54))                           # блик верхней кромки
    d.rectangle([2, 2, w - 3, h - 3], outline=(104, 70, 40), width=2)          # внешняя кромка
    d.rectangle([b - 4, b - 4, w - b + 3, h - b + 3], outline=(34, 20, 11), width=4)  # внутренняя тень
    # паспарту
    mat = (186, 162, 120)
    d.rectangle([b, b, w - b - 1, h - b - 1], fill=mat)
    p = 7                                    # поле паспарту
    x0, y0, x1, y1 = b + p, b + p, w - b - p, h - b - p
    pw, ph = x1 - x0, y1 - y0
    # снимок: фон ателье — светлее к середине, сепия
    yy, xx = np.mgrid[0:ph, 0:pw].astype(np.float32)
    cx, cy = pw * 0.5, ph * 0.42
    rad = np.sqrt(((xx - cx) / pw) ** 2 + ((yy - cy) / ph) ** 2)
    tone = 0.78 - rad * 0.55 + r.normal(0, 0.025, (ph, pw))
    # пол ателье темнее
    tone = np.where(yy > ph * 0.78, tone - 0.12, tone)
    sil = figure_mask().astype(np.float32) / 255
    def put(height_frac: float, cx_frac: float, base_frac: float, shade: float) -> None:
        nonlocal tone
        fh = int(ph * height_frac)
        fw = max(1, int(sil.shape[1] * fh / sil.shape[0]))
        m = np.array(Image.fromarray((sil * 255).astype(np.uint8)).resize((fw, fh), Image.LANCZOS), np.float32) / 255
        top = int(ph * base_frac) - fh
        left = int(pw * cx_frac - fw / 2)
        y_a, y_b = max(top, 0), min(top + fh, ph)
        x_a, x_b = max(left, 0), min(left + fw, pw)
        mm = m[y_a - top:y_b - top, x_a - left:x_b - left]
        body = np.full_like(mm, shade)
        face_h = int(fh * 0.13)
        if face_h > 0:
            fy = np.arange(y_a - top, y_b - top)[:, None]
            body = np.where((fy > fh * 0.03) & (fy < face_h + fh * 0.03), shade + 0.34, body)
        tone[y_a:y_b, x_a:x_b] = tone[y_a:y_b, x_a:x_b] * (1 - mm) + body * mm
    put(0.74, 0.34, 0.9, 0.24)   # взрослая — слева
    put(0.62, 0.70, 0.9, 0.28)   # подросток — справа
    put(0.42, 0.52, 0.93, 0.30)  # ребёнок — впереди посередине
    tone = np.clip(tone, 0, 1)
    t8 = Image.fromarray((tone * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.6))
    t = np.array(t8, np.float32) / 255
    # сепия: тёмно-коричневый → кремовый, лёгкое выцветание и зерно
    dark, light = np.array([58, 36, 20], np.float32), np.array([214, 184, 134], np.float32)
    sep = dark + (light - dark) * t[..., None]
    sep = sep * 0.94 + 8 + r.normal(0, 3.0, (ph, pw))[..., None]
    img.paste(Image.fromarray(np.clip(sep, 0, 255).astype(np.uint8)), (x0, y0))
    d.rectangle([x0 - 1, y0 - 1, x1, y1], outline=(120, 96, 64), width=1)
    return img


def photo_at(width: float, lean: float = 0.94, tone: float = 1.0) -> Image.Image:
    """Рамка шириной `width` px экрана, стоит с наклоном назад (высота × lean), тон × tone."""
    m = photo_master()
    pw = max(4, int(round(width / ART)))                  # в px фона (холст слоя — фон)
    ph = max(5, int(round(pw * PHOTO_ASPECT * lean)))
    im = m.resize((pw * 4, ph * 4), Image.LANCZOS).resize((pw, ph), Image.LANCZOS)
    if tone != 1.0:
        a = np.array(im).astype(np.float32)
        a[:, :, :3] *= tone
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    return im


# --- сборка слоёв --------------------------------------------------------------------------------------

def canvas(w: int = W, h: int = H) -> Image.Image:
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def shadow_blob(size: tuple[int, int], cx: float, cy: float, rx: float, ry: float, alpha: float, blur: float,
                rgb=(30, 20, 12)) -> Image.Image:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=int(255 * alpha))
    m = m.filter(ImageFilter.GaussianBlur(blur))
    return Image.merge("RGBA", (*Image.new("RGB", size, rgb).split(), m))


def drop_shadow(sprite: Image.Image, size: tuple[int, int], pos: tuple[int, int], dx: float, dy: float,
                alpha: float, blur: float, rgb=(30, 20, 12)) -> Image.Image:
    a = sprite.split()[3]
    m = Image.new("L", size, 0)
    m.paste(a, (int(round(pos[0] + dx)), int(round(pos[1] + dy))))
    m = m.point(lambda v: int(v * alpha)).filter(ImageFilter.GaussianBlur(blur))
    return Image.merge("RGBA", (*Image.new("RGB", size, rgb).split(), m))


def local_tone(bg: np.ndarray, x: float, y: float, r: float, ref: float) -> float:
    """Яркость окрестности места (px фона) относительно опорной — тон вещи в тени/на свету."""
    x0, x1 = int(max(x - r, 0)), int(min(x + r, bg.shape[1]))
    y0, y1 = int(max(y - r, 0)), int(min(y + r, bg.shape[0]))
    v = float(lum(bg[y0:y1, x0:x1, :3].astype(np.float32)).mean())
    return float(np.clip(v / ref, 0.55, 1.15))


def place_photo(key: str, wall_shadow: tuple[float, float] | None, tone: float) -> Image.Image:
    x, y, w = PLACES[key]
    sp = photo_at(w, tone=tone)
    bx, by = to_bg(x, y)
    pos = (int(round(bx - sp.width / 2)), int(round(by - sp.height)))
    out = canvas()
    if wall_shadow:
        out.alpha_composite(drop_shadow(sp, (W, H), pos, wall_shadow[0], wall_shadow[1], 0.38, 2.2))
    out.alpha_composite(shadow_blob((W, H), bx - sp.width * 0.08, by, sp.width * 0.62, max(1.6, sp.width * 0.08), 0.55, 1.2))
    out.alpha_composite(sp, pos)
    return out


def place_cup(img: Image.Image, key: str, tone: float, shadow_dx: float, shadow_dy: float) -> Image.Image:
    x, y, w = PLACES[key]
    s = (w / ART) / (MUG_BODY_W * TABLE_S / ART)          # ширина тулова → масштаб выреза
    s_px = TABLE_S / ART * s                              # px слоя → px фона
    cw, ch = max(2, int(round(img.width * s_px))), max(2, int(round(img.height * s_px)))
    sp = img.resize((cw * 4, ch * 4), Image.LANCZOS).resize((cw, ch), Image.LANCZOS)
    if tone != 1.0:
        a = np.array(sp).astype(np.float32)
        a[:, :, :3] *= tone
        sp = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    bx, by = to_bg(x, y)
    base_x = (MUG_BASE[0] - MUG_BOX[0]) * s_px
    base_y = (MUG_BASE[1] - MUG_BOX[1]) * s_px
    pos = (int(round(bx - base_x)), int(round(by - base_y)))
    body_w = MUG_BODY_W * s_px
    out = canvas()
    out.alpha_composite(shadow_blob((W, H), bx + shadow_dx * body_w, by + shadow_dy * body_w, body_w * 0.6,
                                    max(1.5, body_w * 0.13), 0.62, max(0.9, body_w * 0.05)))
    out.alpha_composite(sp, pos)
    return out


ART10A = ROOT / "assets" / "incoming"
ART10A_BASE = {"cup_blue": (256, 437), "cup_white": (256, 437), "mug_blue": (215, 463)}   # середина донца в px 512


def place_art10a(name: str, key: str, tone: float, shadow_dx: float, shadow_dy: float) -> Image.Image:
    """Чашка / кружка партии 10а (512×512, прозрачная) на месте `key`: ширина вещи — по PLACES, донце — в точку места."""
    src = Image.open(ART10A / f"{name}.png").convert("RGBA")
    box = src.getchannel("A").getbbox()
    x, y, w = PLACES[key]
    k = (w / ART) / (box[2] - box[0])                   # px исходника → px фона
    cw, ch = max(2, int(round(src.width * k))), max(2, int(round(src.height * k)))
    sp = src.resize((cw, ch), Image.LANCZOS)
    if tone != 1.0:
        a = np.array(sp).astype(np.float32)
        a[:, :, :3] *= tone
        sp = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    bx, by = to_bg(x, y)
    b0 = ART10A_BASE[name]
    pos = (int(round(bx - b0[0] * k)), int(round(by - b0[1] * k)))
    body_w = (box[2] - box[0]) * k
    out = canvas()
    out.alpha_composite(shadow_blob((W, H), bx + shadow_dx * body_w, by + shadow_dy * body_w, body_w * 0.5,
                                    max(1.5, body_w * 0.09), 0.55, max(0.9, body_w * 0.04)))
    out.alpha_composite(sp, pos)
    return out


def h1_layers() -> dict[str, Image.Image]:
    bg = np.array(Image.open(H1_BG).convert("RGB"))
    tbl = np.array(Image.open(H1_TABLE).convert("RGBA"))
    # опорная яркость — дорожка столика вокруг кружки (как освещена исходная кружка)
    ref = float(lum(tbl[505:520, 760:900, :3].astype(np.float32)).mean())
    out: dict[str, Image.Image] = {}
    def tone_at(key: str, r: float = 14.0) -> float:
        x, y, _w = PLACES[key]
        bx, by = to_bg(x, y)
        return local_tone(bg, bx, by - r * 0.6, r, ref)
    out["state_photo_ledge.png"] = place_photo("photo_ledge", (-2.0, -1.0), tone_at("photo_ledge") * 0.95)
    out["state_photo_table.png"] = place_photo("photo_table", None, 1.0)
    out["state_photo_shelf.png"] = place_photo("photo_shelf", (-1.5, -0.8), tone_at("photo_shelf") * 0.95)
    sill_tone = min(1.0, tone_at("cup_sill_blue", 10.0)) * 0.92   # окно за спиной: вещь в контровом
    if (ART10A / "cup_blue.png").exists():
        # H15/H54: чашки и кружка партии 10а (старорусская роспись), крупнее, по перспективе места.
        out["state_cup_sill_blue.png"] = place_art10a("cup_blue", "cup10_sill_blue", sill_tone, 0.0, 0.05)
        out["state_cup_sill_white.png"] = place_art10a("cup_white", "cup10_sill_white", sill_tone, 0.0, 0.05)
        out["state_cup_table_blue.png"] = place_art10a("cup_blue", "cup10_table", 0.96, -0.12, 0.01)
        out["state_cup_table_white.png"] = place_art10a("cup_white", "cup10_table", 0.96, -0.12, 0.01)
        out["state_mug_table.png"] = place_art10a("mug_blue", "mug10_table", 0.92, -0.15, 0.01)
        return out
    c = cups()
    out["state_cup_sill_blue.png"] = place_cup(c["blue"], "cup_sill_blue", sill_tone, 0.0, 0.12)
    out["state_cup_sill_white.png"] = place_cup(c["white"], "cup_sill_white", sill_tone, 0.0, 0.12)
    out["state_cup_table_blue.png"] = place_cup(c["blue"], "cup_table", 1.0, -0.22, 0.02)
    out["state_cup_table_white.png"] = place_cup(c["white"], "cup_table", 1.0, -0.22, 0.02)
    return out


# --- O1 -------------------------------------------------------------------------------------------------

def chalk_sprite(length_px: float) -> Image.Image:
    ic = Image.open(CHALK_ICON).convert("RGBA")
    a = np.array(ic)[:, :, 3] > 128
    ys, xs = np.where(a)
    ic = ic.crop((xs.min() - 4, ys.min() - 4, xs.max() + 5, ys.max() + 5))
    # ось палочки ≈ 34° вверх-вправо; почти вдоль парты (8° вверх-вправо)
    rot = ic.rotate(-26, resample=Image.BICUBIC, expand=True)
    a = np.array(rot)[:, :, 3] > 40
    ys, xs = np.where(a)
    rot = rot.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    L = length_px / ART
    s = L / rot.width
    w, h = max(3, int(round(rot.width * s))), max(2, int(round(rot.height * s * 0.6)))   # ракурс столешницы
    sp = rot.resize((w * 4, h * 4), Image.LANCZOS).resize((w, h), Image.LANCZOS)
    arr = np.array(sp).astype(np.float32)
    arr[:, :, :3] = arr[:, :, :3] * np.array([0.93, 0.95, 0.98]) + np.array([4, 4, 6])   # холодный свет класса
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def o1_layers() -> dict[str, Image.Image]:
    import cv2
    out: dict[str, Image.Image] = {}
    # мел на парте
    x, y, L = PLACES["chalk_desk"]
    sp = chalk_sprite(L)
    bx, by = to_bg(x, y)
    pos = (int(round(bx - sp.width / 2)), int(round(by - sp.height / 2)))
    c = Image.new("RGBA", (OW, OH), (0, 0, 0, 0))
    c.alpha_composite(drop_shadow(sp, (OW, OH), pos, 1.6, 1.8, 0.62, 1.3, rgb=(26, 16, 10)))
    c.alpha_composite(sp, pos)
    out["state_chalk_desk.png"] = c
    # заплатка учительского стола: мелки фона (экран x 598–650, y 483–494 и x 667–697, y 488–496)
    bg = np.array(Image.open(O1_BG).convert("RGB"))
    mask = np.zeros(bg.shape[:2], np.uint8)
    for (x0, y0, x1, y1) in ((598, 482, 651, 495), (667, 487, 698, 497)):
        a0, b0 = to_bg(x0, y0)
        a1, b1 = to_bg(x1, y1)
        sub = bg[int(b0):int(b1) + 1, int(a0):int(a1) + 1].astype(np.float32)
        light = (lum(sub) > 150) & (sub.max(axis=2) - sub.min(axis=2) < 70)   # белые кусочки мела
        mm = np.zeros(sub.shape[:2], np.uint8)
        mm[light] = 255
        mask[int(b0):int(b1) + 1, int(a0):int(a1) + 1] = np.maximum(mask[int(b0):int(b1) + 1, int(a0):int(a1) + 1], mm)
    mask = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=2)
    fixed = cv2.inpaint(bg[:, :, ::-1].copy(), mask, 4, cv2.INPAINT_TELEA)[:, :, ::-1]
    feather = cv2.GaussianBlur(cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=1), (5, 5), 0)
    patch = np.dstack([fixed, feather]).astype(np.uint8)
    patch[feather == 0] = 0                  # прозрачное — без цвета (файл не раздувается)
    out["patch_teacher_chalk.png"] = Image.fromarray(patch, "RGBA")
    # пометка Агаты на полях картинки с птицей (экран: справа от головы птицы, чистое поле бумаги):
    # строчка скорописью (трохоида — петли разной высоты), заглавная с наклоном в начале, подчёркивание.
    r = rng(3)
    K = 6                                    # рисуем крупно и уменьшаем — мягкий графит
    big = Image.new("L", (OW * K, OH * K), 0)
    d = ImageDraw.Draw(big)
    ox, oy = to_bg(1600, 199)
    ox, oy = ox * K, oy * K
    u = K * 0.87                             # 1 px экрана в px холста
    # заглавная: косая черта вверх и петля вниз
    d.line([(ox, oy + 12 * u), (ox + 4 * u, oy), (ox + 7 * u, oy + 12 * u)], fill=250, width=int(1.5 * u), joint="curve")
    d.line([(ox + 2 * u, oy + 7 * u), (ox + 6 * u, oy + 7 * u)], fill=240, width=int(1.3 * u))
    pts = []
    n = 120
    for i in range(n):
        t = i / (n - 1)
        a = t * 5.5 * 2 * np.pi
        amp = (3.4 + 1.6 * np.sin(t * 9.0 + 1.0)) * u
        px = ox + 10 * u + t * 26 * u + 1.6 * u * np.sin(a)
        py = oy + 9 * u - amp * (0.5 + 0.5 * np.cos(a)) + r.normal(0, 0.08) * u
        pts.append((px, py))
    d.line(pts, fill=245, width=int(1.4 * u), joint="curve")
    d.ellipse([ox + 38 * u, oy + 10 * u, ox + 39.4 * u, oy + 11.4 * u], fill=230)          # точка
    d.line([(ox + 1 * u, oy + 15 * u), (ox + 30 * u, oy + 14.2 * u)], fill=210, width=int(1.2 * u))   # подчёркивание
    m = big.resize((OW, OH), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.3))
    graphite = Image.new("RGB", (OW, OH), (48, 46, 46))
    out["state_bird_mark.png"] = Image.merge("RGBA", (*graphite.split(), m))
    return out


# Верх столика у кружки в px слоя: слева от неё (x 780) y 464, справа (x 885) y 477 — край столешницы.
TABLE_EDGE = ((780.0, 464.0), (885.0, 477.0))


def table_without_mug() -> Image.Image:
    """J (стр. 95): столик без нарисованной глиняной кружки — синяя кружка 10а стала меньше и её больше не закрывает.
    Что выше края столешницы — прозрачно (за ним пол фона), что на дорожке — дорисовано той же дорожкой справа."""
    import cv2
    fg = np.array(Image.open(H1_TABLE).convert("RGBA"))
    m = Image.new("L", (fg.shape[1], fg.shape[0]), 0)
    d = ImageDraw.Draw(m)
    d.polygon(MUG_BODY, fill=255)
    d.polygon(MUG_HANDLE, fill=255)
    mask = cv2.dilate(np.array(m), np.ones((3, 3), np.uint8), iterations=2)
    (x0, y0), (x1, y1) = TABLE_EDGE
    yy, xx = np.mgrid[0:fg.shape[0], 0:fg.shape[1]]
    above = yy < y0 + (xx - x0) * (y1 - y0) / (x1 - x0) + 1.0
    sel = mask > 0
    fill = sel & ~above
    # Дорожка полосатая, полосы идут вдоль края столешницы: пиксель берём той же полосы правее (сдвиг по наклону края),
    # столбцы — справа налево, так что источник уже чистый; шов — мягкий (cv2.inpaint по кромке в 1 px).
    out = fg.copy()
    slope = (y1 - y0) / (x1 - x0)
    shift = 60
    ys, xs = np.where(fill)
    for x in sorted(set(xs.tolist()), reverse=True):
        for y in ys[xs == x]:
            sy, sx = int(round(y + shift * slope)), x + shift
            out[y, x, :3] = out[sy, sx, :3]
    edge = cv2.dilate(fill.astype(np.uint8), np.ones((3, 3), np.uint8)) - cv2.erode(fill.astype(np.uint8), np.ones((3, 3), np.uint8))
    rgb = cv2.inpaint(np.ascontiguousarray(out[:, :, 2::-1]), (edge * 255).astype(np.uint8), 2, cv2.INPAINT_TELEA)[:, :, ::-1]
    e = edge > 0
    out[e & fill, :3] = ((out[e & fill, :3].astype(np.float32) + rgb[e & fill].astype(np.float32)) / 2).astype(np.uint8)
    out[sel & above, 3] = 0
    out[fill, 3] = 255
    return Image.fromarray(out, "RGBA")


def outputs() -> dict[Path, Image.Image]:
    res: dict[Path, Image.Image] = {}
    for name, im in h1_layers().items():
        res[ROOMS / "H1" / name] = im
    res[ROOMS / "H1" / "fg_table_chair_nomug.png"] = table_without_mug()
    for name, im in o1_layers().items():
        res[ROOMS / "O1" / name] = im
    return res


def bbox_screen(im: Image.Image) -> list[int] | None:
    a = np.array(im)[:, :, 3] > 60
    ys, xs = np.where(a)
    if len(xs) == 0:
        return None
    return [int(xs.min() * ART), int(ys.min() * ART), int((xs.max() + 1) * ART + 0.5) - int(xs.min() * ART),
            int((ys.max() + 1) * ART + 0.5) - int(ys.min() * ART)]


def preview(outdir: Path, files: dict[Path, Image.Image]) -> None:
    outdir.mkdir(parents=True, exist_ok=True)
    def comp(room: str, names: list[str], fg: list[tuple[Path, tuple[float, float], float, int]], z_items: dict[str, int]) -> Image.Image:
        bg = Image.open(ROOMS / room / "bg.png").convert("RGBA")
        layers = [(0, bg, (0, 0), 1.0)]
        for p, off, sc, z in fg:
            layers.append((z, Image.open(p).convert("RGBA"), off, sc))
        for n in names:
            layers.append((z_items.get(n, 0), files[ROOMS / room / n], (0, 0), 1.0))
        layers.sort(key=lambda t: t[0])
        canvas_ = Image.new("RGBA", (1920, 1080), (0, 0, 0, 255))
        for _z, im, off, sc in layers:
            s = ART * sc
            canvas_.alpha_composite(im.resize((int(round(im.width * s)), int(round(im.height * s))), Image.LANCZOS), (int(off[0]), int(off[1])))
        return canvas_
    tbl = [(H1_TABLE, TABLE_OFF, 0.6, 950)]
    z = {"state_photo_table.png": 940, "state_cup_table_blue.png": 955, "state_cup_table_white.png": 955}
    comp("H1", ["state_photo_ledge.png", "state_cup_sill_blue.png", "state_cup_sill_white.png"], tbl, z).save(outdir / "H1_before.png")
    comp("H1", ["state_photo_table.png", "state_cup_sill_white.png", "state_cup_table_blue.png"], tbl, z).save(outdir / "H1_table_blue.png")
    comp("H1", ["state_photo_shelf.png", "state_cup_sill_blue.png", "state_cup_table_white.png"], tbl, z).save(outdir / "H1_shelf_white.png")
    zo = {"state_chalk_desk.png": 1081}
    comp("O1", ["patch_teacher_chalk.png", "state_chalk_desk.png", "state_bird_mark.png"], [(O1_DESKS, (0, 0), 1.0, 1080)], zo).save(outdir / "O1_items.png")


def main() -> int:
    files = outputs()
    if "--geometry" in sys.argv:
        print(json.dumps({str(p.relative_to(ROOMS)): bbox_screen(im) for p, im in files.items()}, ensure_ascii=False, indent=1))
        return 0
    if "--preview" in sys.argv:
        preview(Path(sys.argv[sys.argv.index("--preview") + 1]), files)
        return 0
    check = "--check" in sys.argv
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else []
    bad = 0
    for target, im in files.items():
        if only and not any(o in target.name for o in only):
            continue
        if check:
            if not target.exists():
                print(f"нет файла {target.relative_to(ROOT)}")
                bad += 1
                continue
            cur = np.array(Image.open(target).convert("RGBA")).astype(np.int16)
            new = np.array(im.convert("RGBA")).astype(np.int16)
            if cur.shape != new.shape or np.abs(cur - new).max() > 2:
                print(f"расходится: {target.relative_to(ROOT)}")
                bad += 1
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            im.save(target, optimize=True)
            print(f"записан {target.relative_to(ROOT)}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
