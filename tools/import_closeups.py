#!/usr/bin/env python3
"""Крупные планы предметов в игру: assets/incoming/<имя>.png → game/assets/closeups/<имя>.png.

Партия 2 брифа v4 (ChatGPT, 22.10, assets/incoming/_meta_p2/README_RU.txt): closeup_bridge_photo, closeup_ilya_drawing,
closeup_plan — 1672×941, лист на столе. В игре они показываются в крупном плане учительского ящика O1
(data/story/rooms/O1.json → teacher_drawer.view: pictures — снимок и рисунок, papers — план с текстом игры поверх
свободной зоны листа). Копия уменьшается до ширины, в которой её рисует крупный план (WIDTH ниже, ×1,2 на чёткость),
пропорции и кадр не меняются — координаты зоны текста плана (text_rect) остаются в пикселях исходника 1672×941.
Импорт Godot — с потерями (compress/mode=1 в .import): это иллюстрации, а не пиксельная графика.
assets/ не трогаем (зона Codex), пишем только копию игры.

Запуск: python3 tools/import_closeups.py           — записать копии
        python3 tools/import_closeups.py --check   — копии есть и совпадают по размеру с тем, что дал бы импорт
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "incoming"
DST = ROOT / "game" / "assets" / "closeups"
WIDTH = {"closeup_bridge_photo": 840, "closeup_ilya_drawing": 840, "closeup_plan": 1440}


def target_size(w: int, h: int, name: str) -> tuple[int, int]:
    tw = min(w, WIDTH[name])
    return tw, round(h * tw / w)


def main() -> int:
    from PIL import Image
    check = "--check" in sys.argv
    DST.mkdir(parents=True, exist_ok=True)
    bad = 0
    for name in WIDTH:
        im = Image.open(SRC / f"{name}.png").convert("RGB")
        size = target_size(im.width, im.height, name)
        out = DST / f"{name}.png"
        if check:
            ok = out.is_file() and Image.open(out).size == size
            print(f"{'OK  ' if ok else 'DIFF'} {out.relative_to(ROOT)} {size}")
            bad += 0 if ok else 1
            continue
        im.resize(size, Image.LANCZOS).save(out, optimize=True)
        print(f"wrote {out.relative_to(ROOT)} {size[0]}x{size[1]} ← assets/incoming/{name}.png")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
