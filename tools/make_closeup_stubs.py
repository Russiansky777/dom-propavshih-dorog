#!/usr/bin/env python3
"""Временные крупные планы предметов из иконок конвейера (блок 1, 22.10).

Пока ChatGPT не отдал настоящие крупные планы (Docs/BRIEF_CHATGPT_v4.md, партия 2: closeup_bridge_photo.png,
closeup_ilya_drawing.png; заявки assets/manifest.json → O1_closeup_*), учительский ящик O1 показывает рисунки
иконок той же вещи (assets/icons/<имя>.png, Meshy text-to-image, провенанс — Docs/ASSET_PROVENANCE.md / pipeline)
крупно: обрезка по альфе и уменьшение до MAX px по длинной стороне → game/assets/closeups/<имя>.png.
assets/ не трогаем (это зона Codex), пишем только копию игры.

Запуск: python3 tools/make_closeup_stubs.py [имя ...]   (по умолчанию bridge_photo ilya_drawing)
        python3 tools/make_closeup_stubs.py --check      — копии есть и не старше исходников (код 1, если нет)
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "icons"
DST = ROOT / "game" / "assets" / "closeups"
MAX = 720
DEFAULT = ["bridge_photo", "ilya_drawing"]


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    names = args or DEFAULT
    if "--check" in sys.argv:
        bad = [n for n in names if not (DST / f"{n}.png").is_file()
               or (SRC / f"{n}.png").is_file() and (SRC / f"{n}.png").stat().st_mtime > (DST / f"{n}.png").stat().st_mtime + 1]
        print("closeup stubs: OK" if not bad else f"closeup stubs: пересобрать {bad}")
        return 1 if bad else 0
    from PIL import Image
    DST.mkdir(parents=True, exist_ok=True)
    for n in names:
        im = Image.open(SRC / f"{n}.png").convert("RGBA")
        bbox = im.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
        if bbox:
            im = im.crop(bbox)
        k = min(1.0, MAX / max(im.size))
        if k < 1.0:
            im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        im.save(DST / f"{n}.png", optimize=True)
        print(f"  closeups/{n}.png {im.size[0]}x{im.size[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
