#!/usr/bin/env python3
"""Слои-«вклейки» кадров и комнат по данным: персонажи и вещи в готовых картинах (блоки 3–5, 22.10).

Источник истины — поле `compose` у слоя в data/story/rooms/<ID>.json (комнаты и кадры `"frame": true`). Инструмент
рисует для каждого такого слоя полноформатный PNG размера фона (холст 1672×941, слой ставится в (0, 0), масштаб 1:1 —
как все слои поставок) и пишет его по пути из поля `image` (res://… → game/…). В игре слой обычный: if / unless по
флагам, порядок по месту в списке (фигуры за столом — до слоя переднего плана).

compose — персонаж:
  {"char": "nina",            — id персонажа; лист берётся из assets/characters/<набор>/ (набор: CHAR_SET ниже,
                                  tamara → tamara_v3), пока набора нет — заглушка: вид спереди из assets/incoming/cast_v3/
                                  <char>_v1.png (как плоские NPC блока 2);
   "feet": [x, y],            — середина подошв на холсте фона;
   "height": h,               — рост фигуры на холсте, px (по ориентирам картины: дверь, стол, перила);
   "dir": 0..7,               — строка листа (0 анфас, против часовой: 1 — вправо-вниз … как у Агаты);
   "action": "idle", "frame": 0, — действие и столбец листа (у Нины, Ильи, Ульяны, жены Ильи, управляющего —
                                  "talk", 0: их Idle — застывший шаг, ИИ-осмотр спрайтов 22.10; кадр 0 talk — стойка),
   "tint": [r, g, b],         — умножение цвета (свет картины: тёплая свеча, зимний день, сумерки);
   "shadow": 0.35,            — контактная тень (непрозрачность эллипса у ног), 0 — без тени;
   "mirror": false,           — отразить по горизонтали;
   "cut_below": y,            — обрезать ниже этой строки холста (ноги за столом / скамьёй);
   "hide": [[[x, y], …], …],  — многоугольники холста, где фигура скрыта: то, что на картине перед ней (столешница,
                                  кувшин, чашка) — слой под фигурой проступает (G53: Агата сидит за столом);
   "hide_feather": 1.0}       — мягкость края скрытия, px.
compose — вещь (кусок другой картинки):
  {"src": "game/assets/rooms/H1/state_cup_table_blue.png", "crop": [x, y, w, h], "at": [x, y], "width": w,
   "tint": [...], "rotate": градусы, "alpha": 0..1, "shadow": 0, "mirror": false}
Повторный запуск с теми же исходниками даёт те же файлы; --check сверяет без записи (код 1 — расходятся или нет файла).
Когда приходят листы 3D (assets/characters/<имя>/), запуск без правки данных заменяет заглушки фигурами из листов.
Нужен Pillow. Запуск: python3 tools/make_frame_layers.py [--check] [ID …]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter
Image.MAX_IMAGE_PIXELS = None  # листы Агаты 2,25× (G56): сетка pick 34 560 × 6 912 px — свой файл, не «бомба»

ROOT = Path(__file__).resolve().parent.parent
ROOMS = ROOT / "data" / "story" / "rooms"
CHARS = ROOT / "assets" / "characters"
STUBS = ROOT / "assets" / "incoming" / "cast_v3"
CHAR_SET = {"tamara": "tamara_v3"}
ALPHA_MIN = 128


def res_to_path(res: str) -> Path:
    if not res.startswith("res://"):
        raise SystemExit(f"путь {res} должен начинаться с res://")
    return ROOT / "game" / res[len("res://"):]


def canvas_of(room: dict) -> tuple[int, int]:
    bg = room.get("background", {}).get("image", "")
    with Image.open(res_to_path(bg)) as im:
        return im.size


def figure(c: dict) -> Image.Image:
    """The character's picture, cropped to its silhouette (feet at the bottom edge)."""
    cid = c["char"]
    cset = CHAR_SET.get(cid, cid)
    sheet_dir = CHARS / cset
    action = c.get("action", "idle")
    sprites = sheet_dir / "sprites.json"
    if sprites.exists() and (sheet_dir / f"{action}.png").exists():
        meta = json.loads(sprites.read_text(encoding="utf-8"))
        fw, fh = int(meta["frame_w"]), int(meta["frame_h"])
        im = Image.open(sheet_dir / f"{action}.png").convert("RGBA")
        col, row = int(c.get("frame", 0)), int(c.get("dir", 0))
        im = im.crop((col * fw, row * fh, (col + 1) * fw, (row + 1) * fh))
    else:
        im = Image.open(STUBS / f"{cid}_v1.png").convert("RGBA")
    a = im.getchannel("A").point(lambda v: 255 if v >= ALPHA_MIN else 0)
    box = a.getbbox()
    if box is None:
        raise SystemExit(f"{cid}: пустой силуэт")
    return im.crop((box[0], box[1], box[2], box[3]))


def tinted(im: Image.Image, tint) -> Image.Image:
    if not tint:
        return im
    r, g, b, a = im.split()
    r = r.point(lambda v: min(255, int(v * float(tint[0]))))
    g = g.point(lambda v: min(255, int(v * float(tint[1]))))
    b = b.point(lambda v: min(255, int(v * float(tint[2]))))
    return Image.merge("RGBA", (r, g, b, a))


def shadow_ellipse(canvas: Image.Image, cx: float, cy: float, w: float, alpha: float) -> None:
    if alpha <= 0:
        return
    h = max(4.0, w * 0.22)
    sh = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(sh)
    d.ellipse((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), fill=int(255 * alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(max(2.0, h * 0.35)))
    dark = Image.new("RGBA", canvas.size, (12, 8, 4, 0))
    dark.putalpha(sh)
    canvas.alpha_composite(dark)


def render(c: dict, size: tuple[int, int]) -> Image.Image:
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    if "char" in c:
        fig = figure(c)
        h = float(c["height"])
        k = h / fig.size[1]
        fig = fig.resize((max(1, round(fig.size[0] * k)), max(1, round(h))), Image.LANCZOS)
        if c.get("mirror"):
            fig = fig.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        fig = tinted(fig, c.get("tint"))
        fx, fy = float(c["feet"][0]), float(c["feet"][1])
        shadow_ellipse(out, fx, fy, fig.size[0] * 0.75, float(c.get("shadow", 0.35)))
        x0, y0 = round(fx - fig.size[0] / 2), round(fy - fig.size[1])
        layer = Image.new("RGBA", size, (0, 0, 0, 0))
        layer.paste(fig, (x0, y0), fig)
        if "cut_below" in c:
            cut = int(c["cut_below"])
            ImageDraw.Draw(layer).rectangle((0, cut, size[0], size[1]), fill=(0, 0, 0, 0))
        if c.get("hide"):
            keep = Image.new("L", size, 255)
            dk = ImageDraw.Draw(keep)
            for poly in c["hide"]:
                dk.polygon([(float(x), float(y)) for x, y in poly], fill=0)
            fe = float(c.get("hide_feather", 1.0))
            if fe > 0:
                keep = keep.filter(ImageFilter.GaussianBlur(fe))
            layer.putalpha(ImageChops.multiply(layer.getchannel("A"), keep))
        out.alpha_composite(layer)
        return out
    src = Image.open(ROOT / c["src"]).convert("RGBA")
    if "crop" in c:
        x, y, w, h = (int(v) for v in c["crop"])
        src = src.crop((x, y, x + w, y + h))
    if "width" in c:
        k = float(c["width"]) / src.size[0]
        src = src.resize((max(1, round(src.size[0] * k)), max(1, round(src.size[1] * k))), Image.LANCZOS)
    if c.get("mirror"):
        src = src.transpose(Image.Transpose.FLIP_LEFT_RIGHT)   # J (стр. 199): Тихон на ужине — лицом к людям
    if c.get("rotate"):
        src = src.rotate(float(c["rotate"]), resample=Image.BICUBIC, expand=True)
    src = tinted(src, c.get("tint"))
    if "alpha" in c:
        a = src.getchannel("A").point(lambda v: int(v * float(c["alpha"])))
        src.putalpha(a)
    ax, ay = (int(v) for v in c["at"])
    if c.get("shadow"):
        shadow_ellipse(out, ax + src.size[0] / 2, ay + src.size[1], src.size[0] * 0.9, float(c["shadow"]))
    out.alpha_composite(src, (ax, ay)) if ax >= 0 and ay >= 0 else out.paste(src, (ax, ay), src)
    return out


def main() -> int:
    check = "--check" in sys.argv
    only = {a for a in sys.argv[1:] if not a.startswith("--")}
    bad = 0
    for rf in sorted(ROOMS.glob("*.json")):
        if rf.name.startswith("_"):
            continue
        room = json.loads(rf.read_text(encoding="utf-8"))
        if only and room.get("id") not in only:
            continue
        todo = [l for l in room.get("layers", []) if "compose" in l]
        if not todo:
            continue
        size = canvas_of(room)
        for l in todo:
            target = res_to_path(l["image"])
            im = render(l["compose"], size)
            if check:
                same = target.exists() and ImageChops.difference(Image.open(target).convert("RGBA"), im).getbbox() is None
                print(f"{'OK  ' if same else 'DIFF'} {target.relative_to(ROOT)}")
                bad += 0 if same else 1
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                im.save(target, optimize=True)
                print(f"wrote {target.relative_to(ROOT)} ({room['id']}.{l.get('id')})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
