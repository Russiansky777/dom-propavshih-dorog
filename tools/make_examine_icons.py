#!/usr/bin/env python3
"""Large copies of the bag icons for «Рассмотреть» (F9) — the items that have no close-up art yet.

The bag uses 192 px icons (tools/sync_icons.sh); looking at a thing up close shows it ≈ 600 px tall, so a
192 px icon would be blurred. This makes game/assets/examine/<icon>.png at EXAMINE_SIZE from the pipeline's
1024 px originals (assets/icons/<icon>.png, read only): trimmed to the object, padded to a square with a 4 %
margin, Lanczos — the same framing as the bag icon. Imported lossy (WebP) to keep the web build small.
Which items: every inventory item whose items.json `examine` has no `art` (its picture is the icon).

    python3 tools/make_examine_icons.py           # writes the copies (+ .import)
    python3 tools/make_examine_icons.py --check   # exit 1 when a copy is missing
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/icons"
DST = ROOT / "game/assets/examine"
SIZE = 560
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/examine/{name}.png"

[params]

compress/mode=1
compress/lossy_quality=0.85
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=true
process/premult_alpha=false
process/size_limit=0
detect_3d/compress_to=1
"""


def wanted() -> list[str]:
    items = json.loads((ROOT / "data/story/items.json").read_text(encoding="utf-8"))["items"]
    out = []
    for it in items:
        ex = it.get("examine")
        if not it.get("inventory") or not isinstance(ex, dict) or ex.get("art"):
            continue
        out.append(str(it.get("icon") or it["id"]))
    return sorted(set(out))


def make(name: str) -> bool:
    src = SRC / f"{name}.png"
    if not src.exists():
        print(f"  no assets/icons/{name}.png — the bag icon (or its letter patch) is shown")
        return False
    im = Image.open(src).convert("RGBA")
    mask = im.getchannel("A").point(lambda a: 255 if a > 24 else 0)
    obj = im.crop(mask.getbbox() or (0, 0, im.width, im.height))
    side = int(max(obj.width, obj.height) * 1.08)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(obj, ((side - obj.width) // 2, (side - obj.height) // 2))
    DST.mkdir(parents=True, exist_ok=True)
    canvas.resize((SIZE, SIZE), Image.LANCZOS).save(DST / f"{name}.png", optimize=True)
    imp = DST / f"{name}.png.import"
    if not imp.exists():
        imp.write_text(IMPORT.format(name=name), encoding="utf-8")
    return True


def main() -> int:
    names = wanted()
    if "--check" in sys.argv:
        missing = [n for n in names if (SRC / f"{n}.png").exists() and not (DST / f"{n}.png").exists()]
        if missing:
            print("make_examine_icons: missing large copies:", ", ".join(missing))
            return 1
        print(f"make_examine_icons: {len(names)} items use the icon, copies present")
        return 0
    made = [n for n in names if make(n)]
    print(f"make_examine_icons: {len(made)} of {len(names)} written → game/assets/examine")
    return 0


if __name__ == "__main__":
    sys.exit(main())
