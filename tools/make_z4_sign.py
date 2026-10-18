#!/usr/bin/env python3
"""Надпись «ПОЧТА» на доске вывески над дверью почты в переулке Z4 (замечание Директора 18.10: «На табличке
написать "Почта", проверить как это слово писалось в нужные годы и написать старым стилем»).

Доска в арте пустая (assets/incoming/Z4_bg.png, в игре — отражённая копия game/assets/rooms/Z4/bg.png).
Надпись — отдельный слой поверх фона (rooms/Z4.json → layers.post_sign_text), фон не меняется:
  1. буквы набираются шрифтом Old Standard TT Bold (SIL OFL 1.1, уже в игре: game/assets/fonts/old_standard_tt) —
     «обыкновенная» книжная гарнитура конца XIX — начала XX века, такими прописными писали и вывески;
     с разрядкой (разреженный набор — примета вывесок и заголовков того времени);
  2. краска: тёплая белила, слегка пожелтевшая; износ — облетевшие чешуйки по кромкам букв и полосы по
     волокну доски (доска горизонтальна, волокно вдоль неё), чуть прозрачнее там, где краска стёрлась; под
     свежим слоем — бледный след прежних букв, сдвинутых на волос («На старой доске не раз подновляли буквы»,
     @Z4.post_sign.look);
  3. перспектива: буквы кладутся на лицевую плоскость доски преобразованием «прямоугольник → четыре угла
     доски» (cv2.getPerspectiveTransform; углы — rooms/Z4.json → layers.post_sign_text.board, экранные px
     1920x1080, сняты с фона по кромкам доски); отношение сторон доски 2,6 : 1 (при обзоре кадра ≈ 60°
     перспектива краёв даёт 2,3–3,0);
  4. свет: яркость краски повторяет яркость доски под ней (тень под карнизом, свет фонаря) — краска не
     «светится» поверх арта; лёгкое смягчение 0,35 px, как у мазка фона.

Орфография: «ПОЧТА» — так же и до реформы 1917–1918 гг.: слово кончается гласной (ъ ставили только после
конечной согласной), в нём нет ѣ, і, ѳ, ѵ (см. Docs/DECISIONS.md, 18.10 «Вывеска почты»).

Запуск: python3 tools/make_z4_sign.py           — записать game/assets/rooms/Z4/sign_pochta.png
        python3 tools/make_z4_sign.py --check   — сверить файл с тем, что дал бы запуск (код 1 — расходятся)
        python3 tools/make_z4_sign.py --preview OUT.png — крупный кадр доски с надписью (×6) для проверки
Нужны Pillow, numpy, opencv (не в CI: результат лежит в репозитории). Случайность износа — с фиксированным
зерном, повторный запуск даёт тот же файл.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ROOM = ROOT / "data" / "story" / "rooms" / "Z4.json"
BG = ROOT / "game" / "assets" / "rooms" / "Z4" / "bg.png"
OUT = ROOT / "game" / "assets" / "rooms" / "Z4" / "sign_pochta.png"
FONT = ROOT / "game" / "assets" / "fonts" / "old_standard_tt" / "OldStandard-Bold.ttf"
LAYER_ID = "post_sign_text"

TEXT = "ПОЧТА"
ASPECT = 2.6            # ширина : высота лицевой плоскости доски
SRC_H = 1000            # высота доски в исходном (плоском) холсте, px
CAP_H = 0.50            # высота прописных — доля высоты доски
MAX_W = 0.80            # строка не шире этой доли ширины доски (гвозди по углам, поля)
TRACKING = 0.16         # разрядка, доля кегля
OPTICAL_UP = 0.02       # строка чуть выше центра (оптическая середина)
PAINT = np.array([231, 220, 192], dtype=np.float32)   # белила, пожелтевшие
OPACITY = 0.90
GHOST = 0.20            # прежний слой краски
SUPER = 4               # сглаживание: перспектива считается ×4, потом уменьшается
SEED = 1918


def layer_spec() -> dict:
    room = json.loads(ROOM.read_text(encoding="utf-8"))
    for l in room.get("layers", []):
        if l.get("id") == LAYER_ID:
            return l
    raise SystemExit(f"{ROOM}: нет слоя {LAYER_ID}")


def art_scale(bg: Image.Image) -> float:
    return 1920.0 / bg.size[0]


def board_quad_bg(spec: dict, scale: float) -> np.ndarray:
    """Углы лицевой плоскости доски в px фона: TL, TR, BR, BL."""
    q = np.array(spec["board"], dtype=np.float32)
    return q / scale


def noise(shape, sigma_x: float, sigma_y: float, rng) -> np.ndarray:
    import cv2
    n = rng.random(shape, dtype=np.float32)
    n = cv2.GaussianBlur(n, (0, 0), sigmaX=sigma_x, sigmaY=sigma_y)
    n -= n.min()
    return n / max(1e-6, n.max())


def text_mask(w: int, h: int, dx: float = 0.0, dy: float = 0.0) -> np.ndarray:
    """Плоский холст доски w×h с белыми буквами (0..1), строка по центру."""
    probe = ImageFont.truetype(str(FONT), 1000)
    cap = probe.getbbox("П")[3] - probe.getbbox("П")[1]
    size = int(round(1000 * CAP_H * h / cap))
    font = ImageFont.truetype(str(FONT), size)
    track = TRACKING * size

    def line_w(f, tr):
        return sum(f.getlength(c) for c in TEXT) + tr * (len(TEXT) - 1)

    if line_w(font, track) > MAX_W * w:
        k = MAX_W * w / line_w(font, track)
        size = int(size * k)
        font = ImageFont.truetype(str(FONT), size)
        track = TRACKING * size
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    top = font.getbbox("П")[1]
    capf = font.getbbox("П")[3] - top
    x = (w - line_w(font, track)) / 2.0 + dx
    y = (h - capf) / 2.0 - top - OPTICAL_UP * h + dy
    for c in TEXT:
        d.text((x, y), c, font=font, fill=255)
        x += font.getlength(c) + track
    return np.asarray(img, dtype=np.float32) / 255.0


def build(spec: dict) -> tuple[Image.Image, tuple[int, int]]:
    import cv2
    bg = Image.open(BG).convert("RGB")
    scale = art_scale(bg)
    quad = board_quad_bg(spec, scale)
    x0, y0 = np.floor(quad.min(axis=0)).astype(int) - 2
    x1, y1 = np.ceil(quad.max(axis=0)).astype(int) + 2
    W, H = int(round(SRC_H * ASPECT)), SRC_H
    rng = np.random.default_rng(SEED)

    # Paint alpha on the flat board: letters × (1 − wear); a faint older layer under them.
    fresh = text_mask(W, H)
    old = text_mask(W, H, dx=0.018 * H, dy=0.012 * H)
    chips = noise((H, W), 9, 9, rng)                       # облетевшие чешуйки
    chips = np.clip((chips - 0.62) / 0.10, 0, 1)
    grain = noise((H, W), 140, 2.2, rng)                   # полосы по волокну
    grain = np.clip((grain - 0.55) / 0.25, 0, 1) * 0.55
    blot = noise((H, W), 160, 90, rng)                     # где краска истёрлась сильнее
    wear = np.clip(chips + grain + (blot - 0.5) * 0.35, 0, 1)
    edge = cv2.GaussianBlur(fresh, (0, 0), 7) - fresh       # обтрёпанные кромки букв
    rough = noise((H, W), 5, 5, rng)
    a_fresh = fresh * (1 - wear) * OPACITY
    a_fresh *= np.where(np.abs(edge) > 0.05, np.clip(rough * 1.6, 0, 1), 1.0)
    a_old = np.clip(old - fresh, 0, 1) * GHOST * (1 - np.clip(chips * 1.3 + grain, 0, 1))
    alpha = np.clip(a_fresh + a_old, 0, 1)

    # Perspective onto the board face (in bg px of the crop, supersampled).
    src = np.float32([[0, 0], [W, 0], [W, H], [0, H]])
    dst = (quad - np.float32([x0, y0])) * SUPER
    m = cv2.getPerspectiveTransform(src, dst)
    cw, ch = (x1 - x0) * SUPER, (y1 - y0) * SUPER
    a = cv2.warpPerspective(alpha, m, (cw, ch), flags=cv2.INTER_AREA, borderValue=0)
    a = cv2.resize(a, (x1 - x0, y1 - y0), interpolation=cv2.INTER_AREA)
    a = cv2.GaussianBlur(a, (0, 0), 0.35)

    # Light: the paint takes the board's own light (shade under the eaves, the lantern).
    crop = np.asarray(bg.crop((x0, y0, x1, y1)), dtype=np.float32)
    lum = crop @ np.float32([0.299, 0.587, 0.114])
    inside = cv2.warpPerspective(np.ones((H, W), np.float32), m, (cw, ch)) > 0.5
    inside = cv2.resize(inside.astype(np.float32), (x1 - x0, y1 - y0), interpolation=cv2.INTER_AREA) > 0.5
    ref = float(np.median(lum[inside])) if inside.any() else float(lum.mean())
    light = np.clip(lum / max(ref, 1.0), 0.70, 1.20)
    light = cv2.GaussianBlur(light, (0, 0), 1.2)
    rgb = PAINT[None, None, :] * light[..., None]
    rgb = rgb * 0.92 + crop * 0.08                          # краска впитала цвет дерева
    out = np.dstack([np.clip(rgb, 0, 255), np.clip(a * 255.0, 0, 255)]).astype(np.uint8)
    return Image.fromarray(out, "RGBA"), (int(x0), int(y0))


def main() -> int:
    spec = layer_spec()
    img, (x0, y0) = build(spec)
    bg = Image.open(BG)
    scale = art_scale(bg)
    off = [round(x0 * scale, 4), round(y0 * scale, 4)]
    want = [float(v) for v in spec.get("offset", [0, 0])]
    if abs(want[0] - off[0]) > 0.01 or abs(want[1] - off[1]) > 0.01:
        print(f"rooms/Z4.json layers.{LAYER_ID}.offset должен быть {off} (сейчас {want})", file=sys.stderr)
        if "--write-offset" not in sys.argv:
            return 1
    if "--check" in sys.argv:
        if not OUT.exists():
            print(f"нет {OUT}", file=sys.stderr)
            return 1
        cur = np.asarray(Image.open(OUT).convert("RGBA"), dtype=np.int16)
        new = np.asarray(img, dtype=np.int16)
        if cur.shape != new.shape or np.abs(cur - new).max() > 2:
            print(f"{OUT.relative_to(ROOT)} расходится с make_z4_sign.py", file=sys.stderr)
            return 1
        print("OK: sign_pochta.png совпадает")
        return 0
    if "--preview" in sys.argv:
        dest = Path(sys.argv[sys.argv.index("--preview") + 1])
        base = bg.convert("RGBA").crop((x0 - 30, y0 - 25, x0 + img.size[0] + 30, y0 + img.size[1] + 25))
        lay = Image.new("RGBA", base.size, (0, 0, 0, 0))
        lay.paste(img, (30, 25))
        both = Image.alpha_composite(base, lay)
        k = 6
        before = base.resize((base.size[0] * k, base.size[1] * k), Image.LANCZOS)
        after = both.resize((base.size[0] * k, base.size[1] * k), Image.LANCZOS)
        sheet = Image.new("RGBA", (before.size[0] * 2 + 12, before.size[1]), (20, 16, 12, 255))
        sheet.paste(before, (0, 0))
        sheet.paste(after, (before.size[0] + 12, 0))
        sheet.convert("RGB").save(dest)
        print(f"preview → {dest}")
        return 0
    img.save(OUT, optimize=True)
    print(f"→ {OUT.relative_to(ROOT)} {img.size[0]}x{img.size[1]}, offset {off}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
