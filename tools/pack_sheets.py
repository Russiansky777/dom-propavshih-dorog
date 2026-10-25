#!/usr/bin/env python3
"""Листы персонажа → упакованный атлас для игры (копия в game/assets; assets/characters остаётся сеткой).

Зачем (F16, 23.10: «у Агаты будто бы мало fps»): кадров вдвое больше (ходьба 24 на цикл), а в сетке кадр — весь
прямоугольник 384×384, хотя фигура занимает около трети; сетка pick 40 × 384 = 15 360 px — на пределе WebGL.
Атлас: каждый кадр обрезан по фигуре (альфа > 0), разложен полками, между кусками 8 px пустоты и края кратны 4 —
мипмапы (спрайты актёров рисуются с LINEAR_WITH_MIPMAPS) не тянут соседей. В sprites.json игры у действия
появляется "atlas": {"rects": [[x, y, w, h, ox, oy], …] — кадр k = строка·frames + столбец, (ox, oy) — где кусок
лежал в кадре; "size": [W, H]; "src_md5": md5 исходной сетки}. ActorSheet собирает кадр AtlasTexture с margin —
размер и опорная точка кадра те же, что у сетки.

  python3 tools/pack_sheets.py --src assets/characters/<id> --dst game/assets/characters/<id> [--grid]
--grid — копировать сетку как есть (без упаковки). Повторный запуск с тем же исходником ничего не меняет.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path

from PIL import Image
Image.MAX_IMAGE_PIXELS = None  # листы Агаты 2,25× (G56): сетка pick 34 560 × 6 912 px — свой файл, не «бомба»

GAP = 8      # пустота между кусками (px): мипмап 2-го уровня не берёт соседа
ALIGN = 4    # края кусков кратны 4
MAX_SIDE = 8192
# Единица игры — кадр высотой 384 px: под него подобраны масштабы глубины всех комнат. Лист, отрисованный
# крупнее (render_size в запросе конвейера), получает в sprites.json игры texture_scale = frame_h / 384 —
# ActorSheet рисует его в 1/k, рост на экране прежний, деталей в k раз больше (G56)
UNIT_FRAME_H = 384


def md5(p: Path) -> str:
    return hashlib.md5(p.read_bytes()).hexdigest()


def _up(v: int, a: int = ALIGN) -> int:
    return (v + a - 1) // a * a


def pack(sheet: Image.Image, fw: int, fh: int, n: int, dirs: int, max_side: int = MAX_SIDE):
    """→ (страницы-атласы RGBA, rects [[x, y, w, h, ox, oy, page]] по k = d·n + i).

    Ни одна сторона страницы не больше max_side (8192 — предел текстуры WebGL у swiftshader и многих видеокарт;
    T11/I-T2: лист 8832 px по стороне в вебе рисовался чёрным прямоугольником). Не влезло — следующая страница:
    файл <лист>_p<N>.png, номер страницы — седьмое число куска (у первой страницы его нет)."""
    pieces = []
    for d in range(dirs):
        for i in range(n):
            fr = sheet.crop((i * fw, d * fh, (i + 1) * fw, (d + 1) * fh))
            bb = fr.getchannel("A").getbbox()
            if bb is None:
                bb = (0, 0, 1, 1)
            x0, y0 = bb[0] // ALIGN * ALIGN, bb[1] // ALIGN * ALIGN  # смещение в кадре тоже кратно 4
            x1, y1 = min(fw, _up(bb[2])), min(fh, _up(bb[3]))
            pieces.append((d * n + i, fr.crop((x0, y0, x1, y1)), x0, y0))
    area = sum((p[1].width + GAP) * (p[1].height + GAP) for p in pieces)
    width = min(max_side, _up(int(math.sqrt(area * 1.12)), 64))
    order = sorted(pieces, key=lambda p: -p[1].height)
    while True:
        rects, x, y, shelf, page, heights = {}, 0, 0, 0, 0, []
        for k, im, ox, oy in order:
            w, h = im.width, im.height
            if x + w > width:
                x, y, shelf = 0, y + shelf + GAP, 0
            if y + h > max_side:
                heights.append(_up(y - GAP))
                x, y, shelf, page = 0, 0, 0, page + 1
            rects[k] = [x, y, w, h, ox, oy] + ([page] if page else [])
            x += _up(w + GAP)
            shelf = max(shelf, h)
        heights.append(_up(y + shelf))
        if page == 0 or width >= max_side:
            break
        width = min(max_side, width + 512)
    atlases = [Image.new("RGBA", (width, hh), (0, 0, 0, 0)) for hh in heights]
    for k, im, ox, oy in pieces:
        r = rects[k]
        atlases[r[6] if len(r) > 6 else 0].paste(im, (r[0], r[1]))
    return atlases, [rects[k] for k in range(len(pieces))]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--dst", required=True)
    ap.add_argument("--grid", action="store_true", help="копировать сетку как есть")
    args = ap.parse_args()
    src, dst = Path(args.src), Path(args.dst)
    dst.mkdir(parents=True, exist_ok=True)
    meta = json.loads((src / "sprites.json").read_text(encoding="utf-8"))
    old = {}
    if (dst / "sprites.json").exists():
        try:
            old = json.loads((dst / "sprites.json").read_text(encoding="utf-8")).get("actions", {})
        except json.JSONDecodeError:
            old = {}
    fw, fh, dirs = int(meta["frame_w"]), int(meta["frame_h"]), int(meta.get("directions", 8))
    seen, changed, kept = {}, 0, 0
    before = after = 0
    for action, act in list(meta.get("actions", {}).items()):
        if act.get("same_as"):   # та же сетка под другим именем (поза зеркала write_again = write) — атлас общий, ниже
            continue
        sheet = src / act.get("sheet", action + ".png")
        if not sheet.exists():
            continue
        h = md5(sheet)
        out = dst / sheet.name
        if h in seen:
            # дубль другого действия (open_b = open у Meshy) — в игру не копируется, ActorSheet пропускает действие
            print(f"  {dst.name}/{sheet.name} совпадает с {seen[h]} — пропущен")
            out.unlink(missing_ok=True)
            Path(str(out) + ".import").unlink(missing_ok=True)
            continue
        seen[h] = sheet.name
        before += sheet.stat().st_size
        prev = old.get(action, {})
        if args.grid:
            act.pop("atlas", None)
            if not out.exists() or md5(out) != h:
                shutil.copyfile(sheet, out)
                changed += 1
            after += out.stat().st_size
            continue
        if (out.exists() and prev.get("atlas", {}).get("src_md5") == h and int(prev.get("frames", -1)) == int(act["frames"])
                and int(prev["atlas"].get("max_side", 0)) == MAX_SIDE):
            act["atlas"] = prev["atlas"]
            kept += 1
            after += out.stat().st_size
            continue
        n = int(act["frames"])
        # строки листа: направления персонажа или, у поз зеркала, свои строки действия (ходьба — влево и вправо)
        rows = len(act["rows"]) if act.get("rows") else dirs
        atlases, rects = pack(Image.open(sheet).convert("RGBA"), fw, fh, n, rows, MAX_SIDE)
        pages = [sheet.name] + [f"{sheet.stem}_p{p}.png" for p in range(1, len(atlases))]
        for old_page in dst.glob(f"{sheet.stem}_p*.png"):
            if old_page.name not in pages:
                old_page.unlink()
                Path(str(old_page) + ".import").unlink(missing_ok=True)
        for name, atlas in zip(pages, atlases):
            atlas.save(dst / name, optimize=True)
            after += (dst / name).stat().st_size
        act["atlas"] = {"rects": rects, "size": [atlases[0].width, atlases[0].height], "src_md5": h, "gap": GAP,
                        "max_side": MAX_SIDE}
        if len(pages) > 1:
            act["atlas"]["pages"] = pages
            act["atlas"]["page_sizes"] = [[a.width, a.height] for a in atlases]
        changed += 1
        sizes = ", ".join(f"{a.width}×{a.height}" for a in atlases)
        print(f"  {dst.name}/{sheet.name}: сетка {n * fw}×{rows * fh} → атлас {sizes} "
              f"({sum(a.width * a.height for a in atlases) / (n * fw * rows * fh) * 100:.0f} % пикселей)")
    for action, act in meta.get("actions", {}).items():
        ref = meta["actions"].get(act.get("same_as", ""))
        if ref is not None and "atlas" in ref:
            act["atlas"] = ref["atlas"]
    meta["packed"] = not args.grid
    if fh != UNIT_FRAME_H:
        meta["texture_scale"] = round(fh / UNIT_FRAME_H, 6)
    else:
        meta.pop("texture_scale", None)
    text = json.dumps(meta, ensure_ascii=False, indent=2) + "\n"
    if not (dst / "sprites.json").exists() or (dst / "sprites.json").read_text(encoding="utf-8") != text:
        (dst / "sprites.json").write_text(text, encoding="utf-8")
        changed += 1
    print(f"pack_sheets: {dst.name} — {changed} файл(ов) записано, {kept} без изменений; листы {before // 1024} → {after // 1024} КБ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
