#!/usr/bin/env python3
"""Кадры рта Тихона (партия 10г, I-T3): assets/incoming/tikhon_mouth_<n>.png → game/assets/characters/tikhon/mouth_<n>.png.

Исходники — полный холст tikhon_assembled 1254², непустое только в mouth_frames.region (game/data/actors/tikhon.json);
в игру кладётся вырезка этого участка в пикселях исходника (PuppetActor ставит её на кость head, масштаб — как у куклы).
Над носом у кадров окно с альфой 0 (README партии): нос куклы остаётся своим.

Запуск: python3 tools/import_tikhon_mouth.py [--check]   (--check: код 1, если копии не совпадают с вырезкой)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    spec = json.loads((ROOT / "game/data/actors/tikhon.json").read_text(encoding="utf-8"))["mouth_frames"]
    x0, y0, x1, y1 = spec["region"]
    bad = 0
    for i, res in enumerate(spec["images"], 1):
        src = ROOT / "assets/incoming" / f"tikhon_mouth_{i}.png"
        dst = ROOT / "game" / res[len("res://"):]
        im = Image.open(src).convert("RGBA").crop((x0, y0, x1, y1))
        if "--check" in sys.argv:
            ok = dst.is_file() and ImageChops.difference(Image.open(dst).convert("RGBA"), im).getbbox() is None
            print(f"{'ok  ' if ok else 'DIFF'} {dst.relative_to(ROOT)}")
            bad += not ok
        else:
            im.save(dst)
            print(f"wrote {dst.relative_to(ROOT)} {im.size[0]}x{im.size[1]} ← {src.relative_to(ROOT)}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
