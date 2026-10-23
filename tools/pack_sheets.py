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

GAP = 8      # пустота между кусками (px): мипмап 2-го уровня не берёт соседа
ALIGN = 4    # края кусков кратны 4
MAX_SIDE = 8192


def md5(p: Path) -> str:
    return hashlib.md5(p.read_bytes()).hexdigest()


def _up(v: int, a: int = ALIGN) -> int:
    return (v + a - 1) // a * a


def pack(sheet: Image.Image, fw: int, fh: int, n: int, dirs: int):
    """→ (атлас RGBA, rects [[x, y, w, h, ox, oy]] по k = d·n + i)."""
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
    width = min(MAX_SIDE, _up(int(math.sqrt(area * 1.12)), 64))
    order = sorted(pieces, key=lambda p: -p[1].height)
    while True:
        rects, x, y, shelf = {}, 0, 0, 0
        for k, im, ox, oy in order:
            w, h = im.width, im.height
            if x + w > width:
                x, y, shelf = 0, y + shelf + GAP, 0
            rects[k] = [x, y, w, h, ox, oy]
            x += _up(w + GAP)
            shelf = max(shelf, h)
        height = _up(y + shelf)
        if height <= MAX_SIDE or width >= MAX_SIDE:
            break
        width = min(MAX_SIDE, width + 512)
    atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for k, im, ox, oy in pieces:
        r = rects[k]
        atlas.paste(im, (r[0], r[1]))
    return atlas, [rects[k] for k in range(len(pieces))]


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
        if out.exists() and prev.get("atlas", {}).get("src_md5") == h and int(prev.get("frames", -1)) == int(act["frames"]):
            act["atlas"] = prev["atlas"]
            kept += 1
            after += out.stat().st_size
            continue
        n = int(act["frames"])
        atlas, rects = pack(Image.open(sheet).convert("RGBA"), fw, fh, n, dirs)
        atlas.save(out, optimize=True)
        act["atlas"] = {"rects": rects, "size": [atlas.width, atlas.height], "src_md5": h, "gap": GAP}
        changed += 1
        after += out.stat().st_size
        print(f"  {dst.name}/{sheet.name}: сетка {n * fw}×{dirs * fh} → атлас {atlas.width}×{atlas.height} "
              f"({atlas.width * atlas.height / (n * fw * dirs * fh) * 100:.0f} % пикселей), {sheet.stat().st_size // 1024} → {out.stat().st_size // 1024} КБ")
    meta["packed"] = not args.grid
    text = json.dumps(meta, ensure_ascii=False, indent=2) + "\n"
    if not (dst / "sprites.json").exists() or (dst / "sprites.json").read_text(encoding="utf-8") != text:
        (dst / "sprites.json").write_text(text, encoding="utf-8")
        changed += 1
    print(f"pack_sheets: {dst.name} — {changed} файл(ов) записано, {kept} без изменений; листы {before // 1024} → {after // 1024} КБ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
