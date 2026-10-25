#!/usr/bin/env python3
"""I-T4b: кадры жителей из веб-сборки (tools/i_t4b_web.mjs → build/shots/i_t4b/tiles.json) — в листы доказательств:
Docs/evidence/i_t4/web_<id>.jpg (стоит / слушает / говорит ×2 (рот) / идёт) и web_all.jpg (все жители, по ряду).

  python3 tools/i_t4b_tiles.py [--src build/shots/i_t4b] [--out Docs/evidence/i_t4]
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
LABEL = {"idle": "стоит", "listen": "слушает", "talk": "говорит", "walk": "идёт"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(ROOT / "build" / "shots" / "i_t4b"))
    ap.add_argument("--out", default=str(ROOT / "Docs" / "evidence" / "i_t4"))
    a = ap.parse_args()
    rows = json.loads((Path(a.src) / "tiles.json").read_text(encoding="utf-8"))
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    H = 520
    sheets = []
    for r in rows:
        ims = []
        for t in r["tiles"]:
            im = Image.open(t["file"]).convert("RGB")
            im = im.resize((round(im.width * H / im.height), H), Image.LANCZOS)
            ImageDraw.Draw(im).text((6, 6), LABEL.get(t["st"], t["st"]), fill=(255, 255, 255))
            ims.append(im)
        if not ims:
            continue
        sheet = Image.new("RGB", (sum(i.width for i in ims) + 4 * (len(ims) - 1), H + 22), (24, 24, 24))
        ImageDraw.Draw(sheet).text((6, H + 5), f"{r['id']} — {r['room']} (веб, лист characters_web)", fill=(230, 230, 230))
        x = 0
        for i in ims:
            sheet.paste(i, (x, 0))
            x += i.width + 4
        sheet.save(out / f"web_{r['id']}.jpg", quality=86)
        sheets.append(sheet)
    if sheets:
        W = max(s.width for s in sheets)
        allim = Image.new("RGB", (W, sum(s.height for s in sheets)), (24, 24, 24))
        y = 0
        for s in sheets:
            allim.paste(s, (0, y))
            y += s.height
        k = min(1.0, 2400 / allim.width)
        allim.resize((round(allim.width * k), round(allim.height * k)), Image.LANCZOS).save(out / "web_all.jpg", quality=84)
    print(f"{len(sheets)} листов → {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
