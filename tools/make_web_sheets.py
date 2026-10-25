#!/usr/bin/env python3
"""I-T4b (25.10): листы персонажей для веб-сборки — меньше разрешение, только для веба.

Листы k× (sprites.json texture_scale, жители v2 и Агата — 2,25×) в веб-сборке не помещаются в предел сайта
GitHub Pages (1 ГБ): BPTC с мипмапами ≈ 1,33 байта на пиксель атласа. Настольные сборки (Steam) остаются в 2,25×.
Скрипт пишет копии листов в game/assets/characters_web/<id>/ (не в git, собираются в tools/export_web.sh):
каждый кусок атласа уменьшается отдельно (без подмешивания соседей), прямоугольники и поля — в той же доле,
texture_scale в sprites.json = новое разрешение (фигура на экране того же роста, ActorSheet рисует в 1/k).
Веб-сборка с фичей `web_atlas` (export_presets.cfg) берёт лист отсюда, если он есть (ActorSheet.web_sheet_dir).

  python3 tools/make_web_sheets.py                 по таблице SCALES ниже; уже готовые (та же подпись) пропускаются
  python3 tools/make_web_sheets.py --check         код 1, если копии нет или она устарела
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "game" / "assets" / "characters"
DST = ROOT / "game" / "assets" / "characters_web"

# id листа (шаблон) → разрешение веб-копии (texture_scale). Порядок важен: первое совпадение.
SCALES = [
    ("*_v2", 1.0),
    ("agata", 1.5),
]
# импорт веб-копий: как у листов k× — BPTC (BC7) с мипмапами, 1 байт на пиксель в видеопамяти
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/characters_web/{id}/{name}"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.85
mipmaps/generate=true
process/fix_alpha_border=true
process/premult_alpha=false
process/size_limit=0
detect_3d/compress_to=1
"""


def target_scale(sheet_id: str) -> float | None:
    for pat, sc in SCALES:
        if fnmatch.fnmatch(sheet_id, pat):
            return sc
    return None


def signature(src_dir: Path, scale: float) -> str:
    h = hashlib.md5(f"v1 {scale}".encode())
    h.update((src_dir / "sprites.json").read_bytes())
    return h.hexdigest()


def rnd(v: float) -> int:
    return int(round(v))


def make(sheet_id: str, scale: float) -> str:
    src_dir, dst_dir = SRC / sheet_id, DST / sheet_id
    sp = json.loads((src_dir / "sprites.json").read_text(encoding="utf-8"))
    k = float(sp.get("texture_scale", 1.0))
    if k <= scale:
        return "skip (не больше веб-разрешения)"
    sig = signature(src_dir, scale)
    old = dst_dir / "sprites.json"
    if old.exists() and json.loads(old.read_text(encoding="utf-8")).get("web_sheet", {}).get("signature") == sig:
        return "ok (готово)"
    s = scale / k
    if dst_dir.exists():
        shutil.rmtree(dst_dir)
    dst_dir.mkdir(parents=True)
    out = json.loads(json.dumps(sp))
    fw, fh = int(sp["frame_w"]), int(sp["frame_h"])
    out["frame_w"], out["frame_h"] = rnd(fw * s), rnd(fh * s)
    fs = out["frame_h"] / fh  # точная доля по высоте кадра (rects в той же доле)
    out["texture_scale"] = scale
    for action, act in out["actions"].items():
        at = act.get("atlas")
        sheet = act.get("sheet", action + ".png")
        if not (src_dir / sheet).exists():
            continue
        if not at:  # лист-сетка: целиком
            im = Image.open(src_dir / sheet)
            im.resize((rnd(im.width * fs), rnd(im.height * fs)), Image.LANCZOS).save(dst_dir / sheet, optimize=False)
            continue
        pages = at.get("pages", [sheet])
        srcs = [Image.open(src_dir / p).convert("RGBA") for p in pages]
        canv = [Image.new("RGBA", (rnd(im.width * fs) + 2, rnd(im.height * fs) + 2), (0, 0, 0, 0)) for im in srcs]
        rects = []
        for r in at["rects"]:
            x, y, w, h, ox, oy = r[:6]
            pg = int(r[6]) if len(r) > 6 else 0
            nw, nh = max(1, rnd(w * fs)), max(1, rnd(h * fs))
            nx, ny = rnd(x * fs), rnd(y * fs)
            piece = srcs[pg].crop((x, y, x + w, y + h)).resize((nw, nh), Image.LANCZOS)
            canv[pg].paste(piece, (nx, ny))
            nr = [nx, ny, nw, nh, rnd(ox * fs), rnd(oy * fs)] + ([pg] if len(r) > 6 else [])
            # поле не должно выводить кусок за кадр
            nr[4] = max(0, min(nr[4], out["frame_w"] - nw))
            nr[5] = max(0, min(nr[5], out["frame_h"] - nh))
            rects.append(nr)
        at["rects"] = rects
        sizes = []
        for p, c in zip(pages, canv):
            c.save(dst_dir / p)
            sizes.append([c.width, c.height])
        at["size"] = sizes[0]
        if "page_sizes" in at:
            at["page_sizes"] = sizes
        at["src_md5"] = ""
    out["web_sheet"] = {"from": f"res://assets/characters/{sheet_id}", "from_texture_scale": k, "signature": sig}
    for png in dst_dir.glob("*.png"):
        (dst_dir / (png.name + ".import")).write_text(IMPORT.format(id=sheet_id, name=png.name), encoding="utf-8")
    (dst_dir / "sprites.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    return f"сделано: {k}× → {scale}×"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("ids", nargs="*")
    args = ap.parse_args()
    ids = args.ids or sorted(p.name for p in SRC.iterdir() if (p / "sprites.json").exists())
    bad = 0
    for sid in ids:
        sc = target_scale(sid)
        if sc is None:
            continue
        if args.check:
            o = DST / sid / "sprites.json"
            ok = o.exists() and json.loads(o.read_text(encoding="utf-8")).get("web_sheet", {}).get("signature") == signature(SRC / sid, sc)
            print(f"{sid}: {'ok' if ok else 'нет или устарела'}")
            bad += 0 if ok else 1
            continue
        print(f"{sid}: {make(sid, sc)}", flush=True)
    # копии листов, которых больше нет в игре
    if DST.exists() and not args.ids:
        for d in DST.iterdir():
            if d.is_dir() and (target_scale(d.name) is None or not (SRC / d.name / "sprites.json").exists()):
                shutil.rmtree(d)
                print(f"{d.name}: удалена (листа нет)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
