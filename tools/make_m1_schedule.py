#!/usr/bin/env python3
"""Лист «Распорядок смен» на доске двора мельницы M1 и крупный план доски (замечание Директора 23.10, F19:
«на ней ничего не висит и не написано… чтобы можно было приблизить, как карту на почте»).

Доска в арте пустая (game/assets/rooms/M1/bg.png, ChatGPT v3). Фон не меняется — два новых файла:
  1. game/assets/rooms/M1/state_schedule_sheet.png — слой комнаты (rooms/M1.json → layers.schedule_sheet):
     бумажный лист на досках доски, приколот четырьмя гвоздями, по нему — строки «почерком» (штрихи, не
     буквы: в кадре комнаты лист ≈ 140 px, текст всё равно не читается — читается в крупном плане);
     тон листа приглушён под тень навеса (лист не «светится» поверх арта), тень от листа на доски;
  2. game/assets/closeups/closeup_shift_board.png — крупный план (rooms/M1.json → hotspots.schedule.view):
     доска из того же арта (вырезка вокруг доски, увеличенная, с лёгким зерном и виньеткой) и тот же лист
     крупно, чистый — слова пишет игра (view.papers с "sheet": "none": заголовок и текст из
     data/story/text/ru_world.json). Это временный крупный план: живописный — заявка партии 8 ChatGPT
     (assets/manifest.json → M1_schedule_closeup); когда он придёт, поменять image и text_rect в данных.

Геометрия: внутреннее поле доски (доски между рамой) в пикселях исходника фона 1672×941 —
BOARD_INNER; вырезка крупного плана — CROP (рама и немного брёвен вокруг); лист — SHEET в долях
внутреннего поля. Один лист — один и тот же рисунок в обоих файлах (зерно SEED).

Запуск: python3 tools/make_m1_schedule.py           — записать оба файла и напечатать offset слоя и
                                                     прямоугольник текста для данных
        python3 tools/make_m1_schedule.py --check   — сверить файлы с тем, что дал бы запуск (код 1 — расходятся)
Нужны Pillow и numpy (не в CI: результат лежит в репозитории).
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
BG = ROOT / "game" / "assets" / "rooms" / "M1" / "bg.png"
OUT_LAYER = ROOT / "game" / "assets" / "rooms" / "M1" / "state_schedule_sheet.png"
OUT_CLOSE = ROOT / "game" / "assets" / "closeups" / "closeup_shift_board.png"

ART_W = 1672                      # ширина исходника фона; экран 1920
SCREEN_K = 1920.0 / ART_W
BOARD_INNER = (755, 273, 911, 368)  # доски между рамой (x0, y0, x1, y1), px исходника
CROP = (727, 251, 949, 393)       # вырезка крупного плана: вся доска с рамой и краем брёвен (≈ 1,56 : 1)
CLOSE_W = 1440                    # ширина крупного плана, px (в игре — 1:1)
SHEET = (0.15, 0.10, 0.85, 0.90)  # лист в долях внутреннего поля (x0, y0, x1, y1): альбомный, как доска
SHEET_ANGLE = -1.2                # градусы (лист чуть косо)
ROOM_TONE = (0.72, 0.64, 0.54)    # лист в тени навеса: множитель RGB (бумага светлее досок, но не светится)
SEED = 1923


def _noise(rng, h, w, cell):
    """Плавный шум 0..1 с размером пятна ≈ cell px."""
    small = rng.random((max(2, h // cell + 2), max(2, w // cell + 2)))
    im = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32) / 255.0


def make_sheet(w: int, h: int, seed: int) -> np.ndarray:
    """Старая писчая бумага RGBA (float 0..1): желтизна, пятна сырости, волокно, тёмные края, неровная кромка."""
    rng = np.random.default_rng(seed)
    base = np.array([0.86, 0.81, 0.69], dtype=np.float32)
    stain = _noise(rng, h, w, max(8, w // 6))
    fibre = _noise(rng, h, w, 3)
    fibre_h = np.asarray(Image.fromarray((fibre * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(1)), dtype=np.float32) / 255.0
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)) / max(min(w, h) * 0.09, 1.0)
    edge = np.clip(edge, 0.0, 1.0)
    k = 0.92 + 0.10 * stain + 0.07 * (fibre_h - 0.5)
    k *= 0.80 + 0.20 * edge
    rgb = base[None, None, :] * k[..., None]
    rgb[..., 2] *= 0.96 + 0.04 * edge          # края желтее
    # Ржавые точки (foxing) и одно пятно сырости у угла.
    for _ in range(max(3, (w * h) // 9000)):
        cx, cy = rng.random() * w, rng.random() * h
        r = 0.6 + rng.random() * max(1.0, w / 260.0)
        d = np.hypot(xx - cx, yy - cy)
        spot = np.clip(1.0 - d / r, 0, 1)[..., None]
        rgb *= 1.0 - spot * np.array([0.10, 0.15, 0.24], dtype=np.float32)   # ржавое: синего меньше
    cx, cy, r = w * 0.86, h * 0.80, min(w, h) * 0.22
    d = np.hypot(xx - cx, yy - cy)
    ring = np.exp(-((d - r) / (r * 0.10)) ** 2) * 0.045 + np.clip(1 - d / r, 0, 1) * 0.03
    rgb *= (1.0 - ring)[..., None]
    # Лист сложен вчетверо: сгиб — светлая и тёмная полоска рядом, по волокну.
    for pos, axis in ((0.5, 1), (0.5, 0)):
        c = (w if axis == 1 else h) * (pos + (rng.random() - 0.5) * 0.04)
        t = (xx if axis == 1 else yy) - c
        wid = max(1.0, min(w, h) / 260.0)
        rgb *= (1.0 - 0.07 * np.exp(-((t - wid) / wid) ** 2) + 0.04 * np.exp(-((t + wid) / wid) ** 2))[..., None]
    # Неровная кромка.
    jit = (_noise(rng, h, w, max(3, w // 60)) - 0.5) * 2.0
    margin = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)) + jit * max(1.0, w / 400.0)
    alpha = np.clip(margin - 0.5, 0.0, 1.0)
    return np.dstack([np.clip(rgb, 0, 1), alpha]).astype(np.float32)


def add_nails(img: np.ndarray, pts, r: float) -> np.ndarray:
    """Гвозди: тёмная шляпка с бликом и ржавый подтёк вниз."""
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    for (px, py) in pts:
        d = np.hypot(xx - px, yy - py)
        streak = np.exp(-((xx - px) / (r * 0.6)) ** 2) * np.clip((yy - py) / (r * 7.0), 0, 1) * np.clip(1 - (yy - py) / (r * 9.0), 0, 1)
        img[..., :3] *= 1.0 - streak[..., None] * np.array([0.12, 0.20, 0.30], dtype=np.float32)   # ржавый подтёк
        head = np.clip(1.0 - (d - r) / 1.2, 0, 1)
        col = np.array([0.16, 0.13, 0.11], dtype=np.float32)
        img[..., :3] = img[..., :3] * (1 - head[..., None]) + col * head[..., None]
        hl = np.exp(-(np.hypot(xx - (px - r * 0.35), yy - (py - r * 0.35)) / (r * 0.35)) ** 2) * 0.45 * head
        img[..., :3] = np.clip(img[..., :3] + hl[..., None], 0, 1)
        img[..., 3] = np.maximum(img[..., 3], head)
    return img


def scribble(img: np.ndarray, rect, rows: int, seed: int, title: bool) -> np.ndarray:
    """Строки «почерком» (короткие штрихи) в прямоугольнике rect (x0, y0, x1, y1) — для мелкого листа в комнате."""
    rng = np.random.default_rng(seed)
    h, w = img.shape[:2]
    pil = Image.new("L", (w * 4, h * 4), 0)
    dr = ImageDraw.Draw(pil)
    x0, y0, x1, y1 = [v * 4 for v in rect]
    step = (y1 - y0) / rows
    for i in range(rows):
        y = y0 + step * (i + 0.5)
        if title and i == 0:
            xa, xb, width = x0 + (x1 - x0) * 0.22, x0 + (x1 - x0) * 0.78, 7
        else:
            xa, xb, width = x0, x0 + (x1 - x0) * (0.55 + 0.4 * rng.random()), 5
        x = xa
        while x < xb:
            seg = (6 + rng.random() * 18) * 4
            dr.line([(x, y + rng.normal(0, 1.2)), (min(x + seg, xb), y + rng.normal(0, 1.2))], fill=210, width=width)
            x += seg + 4 + rng.random() * 8
    ink = np.asarray(pil.resize((w, h), Image.LANCZOS), dtype=np.float32) / 255.0
    col = np.array([0.20, 0.16, 0.12], dtype=np.float32)
    a = np.clip(ink * 1.5, 0, 1)[..., None] * img[..., 3:4]
    img[..., :3] = img[..., :3] * (1 - a) + col * a
    return img


def rotate_rgba(img: np.ndarray, deg: float) -> np.ndarray:
    pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA")
    pil = pil.rotate(deg, resample=Image.BICUBIC, expand=True)
    return np.asarray(pil, dtype=np.float32) / 255.0


def shadow_of(img: np.ndarray, blur: float, off: tuple[int, int], strength: float, size: tuple[int, int], at: tuple[int, int]) -> np.ndarray:
    """Маска тени листа (0..1) на холсте size, лист в позиции at, сдвиг off, размытие blur."""
    W, H = size
    a = Image.fromarray((img[..., 3] * 255).astype(np.uint8))
    can = Image.new("L", (W, H), 0)
    can.paste(a, (at[0] + off[0], at[1] + off[1]))
    can = can.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(can, dtype=np.float32) / 255.0 * strength


def over(dst: np.ndarray, src: np.ndarray, at: tuple[int, int]) -> np.ndarray:
    """src RGBA поверх dst RGB(A) в позиции at (обрезка по краям)."""
    H, W = dst.shape[:2]
    h, w = src.shape[:2]
    x, y = at
    sx0, sy0 = max(0, -x), max(0, -y)
    dx0, dy0 = max(0, x), max(0, y)
    ww, hh = min(w - sx0, W - dx0), min(h - sy0, H - dy0)
    if ww <= 0 or hh <= 0:
        return dst
    s = src[sy0:sy0 + hh, sx0:sx0 + ww]
    a = s[..., 3:4]
    d = dst[dy0:dy0 + hh, dx0:dx0 + ww]
    d[..., :3] = d[..., :3] * (1 - a) + s[..., :3] * a
    if dst.shape[2] == 4:
        d[..., 3:4] = a + d[..., 3:4] * (1 - a)
    return dst


def sheet_geometry(scale: float):
    """Лист в пикселях холста с масштабом scale относительно исходника фона: (x0, y0, w, h)."""
    ix0, iy0, ix1, iy1 = BOARD_INNER
    iw, ih = ix1 - ix0, iy1 - iy0
    x0 = ix0 + SHEET[0] * iw
    y0 = iy0 + SHEET[1] * ih
    return x0 * scale, y0 * scale, (SHEET[2] - SHEET[0]) * iw * scale, (SHEET[3] - SHEET[1]) * ih * scale


def build_closeup():
    bg = Image.open(BG).convert("RGB")
    cx0, cy0, cx1, cy1 = CROP
    k = CLOSE_W / (cx1 - cx0)
    H = int(round((cy1 - cy0) * k))
    crop = bg.crop(CROP).resize((CLOSE_W, H), Image.LANCZOS)
    rng = np.random.default_rng(SEED + 7)
    a = np.asarray(crop, dtype=np.float32) / 255.0
    a = a * (0.97 + 0.06 * _noise(rng, H, CLOSE_W, 2)[..., None]) * (0.96 + 0.08 * _noise(rng, H, CLOSE_W, 40)[..., None])
    yy, xx = np.mgrid[0:H, 0:CLOSE_W].astype(np.float32)
    vig = 1.0 - 0.28 * np.clip(np.hypot((xx - CLOSE_W / 2) / (CLOSE_W / 2), (yy - H / 2) / (H / 2)) - 0.45, 0, 1)
    a *= vig[..., None]
    # Лист крупно (холст этого масштаба: исходник → ×k, начало — угол вырезки).
    sx, sy, sw, sh = sheet_geometry(k)
    sx -= cx0 * k
    sy -= cy0 * k
    sheet = make_sheet(int(sw), int(sh), SEED)
    r = max(5.0, sw / 95.0)
    sheet = add_nails(sheet, [(r * 2.6, r * 2.6), (sw - r * 2.6, r * 2.6), (r * 2.6, sh - r * 2.6), (sw - r * 2.6, sh - r * 2.6)], r)
    rot = rotate_rgba(sheet, -SHEET_ANGLE)   # PIL: против часовой при +; в игре angle_deg по часовой
    at = (int(sx + sw / 2 - rot.shape[1] / 2), int(sy + sh / 2 - rot.shape[0] / 2))
    sh_mask = shadow_of(rot, 9, (10, 14), 0.55, (CLOSE_W, H), at)
    a *= (1 - sh_mask)[..., None]
    a = over(a, rot, at)
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGB")
    return img, (sx, sy, sw, sh), k


def build_layer():
    """Лист в комнате: в пикселях исходника фона (слой рисуется масштабом фона), offset — экранные px."""
    sx, sy, sw, sh = sheet_geometry(1.0)
    S = 4                                           # рисуем ×4 и уменьшаем — мягкий край, как у мазка фона
    sheet = make_sheet(int(round(sw * S)), int(round(sh * S)), SEED)
    r = max(1.6 * S, sw * S / 95.0)
    W4, H4 = sheet.shape[1], sheet.shape[0]
    sheet = add_nails(sheet, [(r * 2.6, r * 2.6), (W4 - r * 2.6, r * 2.6), (r * 2.6, H4 - r * 2.6), (W4 - r * 2.6, H4 - r * 2.6)], r)
    m = 0.12
    sheet = scribble(sheet, (W4 * 0.10, H4 * m, W4 * 0.47, H4 * (1 - m)), 8, SEED + 1, False)
    sheet = scribble(sheet, (W4 * 0.53, H4 * m, W4 * 0.90, H4 * (1 - m)), 8, SEED + 2, False)
    sheet = scribble(sheet, (W4 * 0.30, H4 * 0.02, W4 * 0.70, H4 * 0.12), 1, SEED + 3, True)
    rot = rotate_rgba(sheet, -SHEET_ANGLE)
    pad = 6 * S
    Wc, Hc = rot.shape[1] + pad * 2, rot.shape[0] + pad * 2
    can = np.zeros((Hc, Wc, 4), dtype=np.float32)
    shadow = shadow_of(rot, 2.2 * S, (int(1.2 * S), int(1.8 * S)), 0.45, (Wc, Hc), (pad, pad))
    can[..., 3] = shadow
    can = over(can, rot, (pad, pad))
    can[..., :3] *= np.array(ROOM_TONE, dtype=np.float32)
    shade = np.linspace(0.86, 1.0, Hc, dtype=np.float32)[:, None, None]   # верх листа — в тени навеса
    can[..., :3] *= shade
    small = Image.fromarray((np.clip(can, 0, 1) * 255).astype(np.uint8), "RGBA").resize((Wc // S, Hc // S), Image.LANCZOS)
    # Верхний левый угол слоя в исходнике → экран (offset).
    ox = (sx + sw / 2) - (Wc / S) / 2
    oy = (sy + sh / 2) - (Hc / S) / 2
    return small, (round(ox * SCREEN_K, 1), round(oy * SCREEN_K, 1))


def main() -> int:
    check = "--check" in sys.argv
    close, (sx, sy, sw, sh), k = build_closeup()
    layer, offset = build_layer()
    if check:
        bad = []
        for img, path in ((close, OUT_CLOSE), (layer, OUT_LAYER)):
            if not path.exists():
                bad.append(f"нет {path.relative_to(ROOT)}")
                continue
            old = np.asarray(Image.open(path), dtype=np.int16)
            new = np.asarray(img, dtype=np.int16)
            if old.shape != new.shape or np.abs(old - new).max() > 2:
                bad.append(f"{path.relative_to(ROOT)} расходится с генератором")
        for b in bad:
            print("make_m1_schedule: " + b)
        print("make_m1_schedule: " + ("OK" if not bad else "FAIL"))
        return 1 if bad else 0
    OUT_CLOSE.parent.mkdir(parents=True, exist_ok=True)
    close.save(OUT_CLOSE, optimize=True)
    layer.save(OUT_LAYER, optimize=True)
    print(f"closeup {OUT_CLOSE.relative_to(ROOT)} {close.size}; лист в крупном плане x {sx:.0f} y {sy:.0f} w {sw:.0f} h {sh:.0f} (px картинки), angle {SHEET_ANGLE}")
    print(f"layer {OUT_LAYER.relative_to(ROOT)} {layer.size}; offset (экран) {offset}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
