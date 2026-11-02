#!/usr/bin/env python3
"""Кадры tools/render_sheet_clips.py → действие копии игры (атлас как у tools/pack_sheets.py).

  python3 tools/pack_sheet_clips.py --work /tmp/w/nina --set nina_v2 --actions talk_steady [--base assets/characters/nina_v2/sprites.json]

Для каждого действия: кадры <work>/<действие>/<d>_<iii>.png (строка d — направление); строки, которых нет в work,
берутся из прежнего атласа этого действия в копии игры (добавление направлений позже — без перерендера готовых), иначе
пусты. Атлас — pack_sheets.pack (обрезка по фигуре, полки, сторона ≤ 8192, страницы _p<N>), в sprites.json копии
игры у действия: описание из <work>/<действие>/action.json, atlas (src_md5 — md5 пикселей сетки), "game_only": true
(сетки в assets/ нет) и "rows": направления, которые отрендерены (make_frame_layers не берёт пустую строку).
Нет sprites.json в копии игры — создаётся по --base (размер кадра, опорная точка, направления) и .gdignore (листы
только для инструментов кадров; игра их не грузит).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import pack_sheets  # noqa: E402

Image.MAX_IMAGE_PIXELS = None


def old_cells(dst: Path, act: dict, fw: int, fh: int, row: int):
    atl = act.get("atlas")
    if not atl or row not in act.get("rows", []):
        return None
    n = int(act["frames"])
    pages = atl.get("pages") or [act.get("sheet")]
    ims = {}
    out = []
    for i in range(n):
        r = atl["rects"][row * n + i]
        p = r[6] if len(r) > 6 else 0
        if p not in ims:
            ims[p] = Image.open(dst / pages[p]).convert("RGBA")
        c = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        c.paste(ims[p].crop((r[0], r[1], r[0] + r[2], r[1] + r[3])), (r[4], r[5]))
        out.append(c)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--set", required=True)
    ap.add_argument("--actions", nargs="+", required=True)
    ap.add_argument("--base", default="", help="sprites.json для новой копии игры (размер кадра и т. п.)")
    ap.add_argument("--meta", default="", help="JSON: поля верхнего уровня новой копии (name, _source…)")
    args = ap.parse_args()
    work = Path(args.work)
    dst = ROOT / "game" / "assets" / "characters" / args.set
    dst.mkdir(parents=True, exist_ok=True)
    sp = dst / "sprites.json"
    if sp.exists():
        meta = json.loads(sp.read_text(encoding="utf-8"))
    else:
        base = json.loads(Path(args.base).read_text(encoding="utf-8"))
        meta = {k: base[k] for k in ("name", "frame_w", "frame_h", "pivot", "directions", "direction_order",
                                     "character_height_m") if k in base}
        meta["actions"] = {}
        if base.get("matte_materials"):
            meta["matte_materials"] = True
        (dst / ".gdignore").write_text("", encoding="utf-8")
    if args.meta:
        meta.update(json.loads(args.meta))
    rep = json.loads((work / "render_report.json").read_text(encoding="utf-8"))
    fw, fh, dirs = int(meta["frame_w"]), int(meta["frame_h"]), int(meta.get("directions", 8))
    if (rep["frame_w"], rep["frame_h"]) != (fw, fh):
        raise SystemExit(f"кадр рендера {rep['frame_w']}×{rep['frame_h']} ≠ листа {fw}×{fh}")
    for action in args.actions:
        am = json.loads((work / action / "action.json").read_text(encoding="utf-8"))
        n = int(am["frames"])
        prev = meta["actions"].get(action, {})
        if prev and int(prev.get("frames", n)) != n:
            prev = {}
        grid = Image.new("RGBA", (fw * n, fh * dirs), (0, 0, 0, 0))
        rows = []
        for d in range(dirs):
            files = [work / action / f"{d}_{i:03d}.png" for i in range(n)]
            if all(f.exists() for f in files):
                cells = [Image.open(f).convert("RGBA") for f in files]
            else:
                cells = old_cells(dst, prev, fw, fh, d)
            if cells is None:
                continue
            for i, c in enumerate(cells):
                grid.paste(c, (i * fw, d * fh))
            rows.append(d)
        if not rows:
            raise SystemExit(f"{action}: нет ни одного направления")
        h = hashlib.md5(grid.tobytes()).hexdigest()
        atlases, rects = pack_sheets.pack(grid, fw, fh, n, dirs, pack_sheets.MAX_SIDE)
        sheet = am.get("sheet", f"{action}.png")
        stem = Path(sheet).stem
        pages = [sheet] + [f"{stem}_p{p}.png" for p in range(1, len(atlases))]
        for old_page in dst.glob(f"{stem}_p*.png"):
            if old_page.name not in pages:
                old_page.unlink()
        for name, atlas in zip(pages, atlases):
            atlas.save(dst / name, optimize=True)
        am["atlas"] = {"rects": rects, "size": [atlases[0].width, atlases[0].height], "src_md5": h,
                       "gap": pack_sheets.GAP, "max_side": pack_sheets.MAX_SIDE}
        if len(pages) > 1:
            am["atlas"]["pages"] = pages
            am["atlas"]["page_sizes"] = [[a.width, a.height] for a in atlases]
        am["game_only"] = True
        am["rows"] = rows
        meta["actions"][action] = am
        print(f"  {args.set}/{action}: направления {rows}, атлас " + ", ".join(f"{a.width}×{a.height}" for a in atlases)
              + f" ({sum((dst / p).stat().st_size for p in pages) // 1024} КБ)", flush=True)
    meta["packed"] = True
    if fh != pack_sheets.UNIT_FRAME_H:
        meta["texture_scale"] = round(fh / pack_sheets.UNIT_FRAME_H, 6)
    sp.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
