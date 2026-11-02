#!/usr/bin/env python3
"""Правки дефектов генератора в картинках, что импортируются не по art_source комнат (крупные планы, головоломки):
оригинал в assets/incoming не меняется, в игру кладётся правленая копия (K, 31.10).

    python3 tools/retouch_art.py          — записать копии
    python3 tools/retouch_art.py --check  — сверить (код 1 — копия в игре не та, что дала бы правка)
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
# игра ← (оригинал, модуль правки с retouch(im) -> im)
TABLE = {
    "game/assets/puzzle/M05/beam.png": ("assets/incoming/M05_beam.png", "tools/retouch/M05_beam.py"),
    "game/assets/puzzle/M05/drawing.png": ("assets/incoming/M05_drawing.png", "tools/retouch/M05_drawing.py"),
    "game/assets/rooms/H1/state_shelf_A.png": ("assets/incoming/H1_state_shelf_A_wide.png", "tools/retouch/H1_shelf_stove.py"),
    "game/assets/rooms/H1/state_holes_stove.png": ("assets/incoming/H1_state_holes_stove_wide.png", "tools/retouch/H1_shelf_stove.py"),
    "game/assets/closeups/O3_clock_hi_bg.png": ("assets/incoming/O3_clock_hi_bg.png", "tools/retouch/O3_clock_hi_bg.py"),
    "game/assets/closeups/O3_clock_hi_pendulum.png": ("assets/incoming/O3_clock_hi_pendulum.png", "tools/retouch/identity.py"),
    "game/assets/closeups/O3_clock_hi_hand_min.png": ("assets/incoming/O3_clock_hi_hand_min.png", "tools/retouch/identity.py"),
    "game/assets/closeups/O3_clock_hi_hand_hour.png": ("assets/incoming/O3_clock_hi_hand_hour.png", "tools/retouch/identity.py"),
    "game/assets/rooms/Z3/state_plate_ring_dusk.png": ("assets/incoming/Z3_state_plate_rope_dusk.png", "tools/retouch/Z3_plate_no_rope.py"),
    "game/assets/ui/map/zarechye_plan.png": ("assets/incoming/map/zarechye_plan.png", "tools/retouch/zarechye_plan.py"),
    "game/assets/ui/map/zarechye_plan_rope.png": ("assets/incoming/map/zarechye_plan.png", "tools/retouch/zarechye_plan_rope.py"),
}


def main() -> int:
    check = "--check" in sys.argv
    bad = 0
    for dst, (src, mod_path) in TABLE.items():
        spec = importlib.util.spec_from_file_location("retouch_mod", ROOT / mod_path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        im = mod.retouch(Image.open(ROOT / src))
        target = ROOT / dst
        if check:
            same = target.exists() and ImageChops.difference(Image.open(target).convert(im.mode), im).getbbox() is None
            print(f"{'OK  ' if same else 'DIFF'} {dst} ← {src} ({mod_path})")
            bad += 0 if same else 1
        else:
            im.save(target, optimize=True)
            print(f"wrote {dst} ← {src} ({mod_path})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
