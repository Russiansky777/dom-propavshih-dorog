#!/usr/bin/env python3
"""I-T4b: кадр жителя в вебе (копия листа, tools/make_web_sheets.py) и на ПК (лист 2,25×) рядом, в одном экранном размере:
Docs/evidence/i_t4/web_vs_pc_<id>.jpg — слева ПК, справа веб; верх — высота кадра 576 px (окно 1080p), низ — 864 px (крупно).
  python3 tools/i_t4b_web_vs_pc.py nina_v2 pavel_v2 ..."""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw
Image.MAX_IMAGE_PIXELS = None
ROOT = Path(__file__).resolve().parent.parent


def frame(d: Path, action: str, row: int, i: int) -> Image.Image:
    sp = json.loads((d / "sprites.json").read_text(encoding="utf-8"))
    act = sp["actions"][action]
    at = act["atlas"]
    r = at["rects"][row * act["frames"] + i]
    page = at.get("pages", [act["sheet"]])[r[6] if len(r) > 6 else 0]
    im = Image.open(d / page).convert("RGBA").crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))
    out = Image.new("RGBA", (sp["frame_w"], sp["frame_h"]), (0, 0, 0, 0))
    out.paste(im, (r[4], r[5]))
    return out


for sid in sys.argv[1:]:
    pc = frame(ROOT / "game/assets/characters" / sid, "talk", 1, 3)
    web = frame(ROOT / "game/assets/characters_web" / sid, "talk", 1, 3)
    rows = []
    for h in (576, 864):
        tiles = []
        for im, label in ((pc, "ПК 2,25×"), (web, "веб 1×")):
            t = Image.new("RGBA", (round(h * 0.75), h), (96, 92, 86, 255))
            s = im.resize((round(im.width * h / im.height), h), Image.LANCZOS)
            t.alpha_composite(s, ((t.width - s.width) // 2, 0))
            ImageDraw.Draw(t).text((8, 8), f"{label}, кадр {h} px", fill=(255, 255, 255, 255))
            tiles.append(t)
        row = Image.new("RGBA", (sum(t.width for t in tiles), h))
        x = 0
        for t in tiles:
            row.paste(t, (x, 0)); x += t.width
        rows.append(row)
    sheet = Image.new("RGBA", (max(r.width for r in rows), sum(r.height for r in rows)))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height
    out = ROOT / "Docs/evidence/i_t4" / f"web_vs_pc_{sid}.jpg"
    sheet.convert("RGB").save(out, quality=88)
    print(out)
