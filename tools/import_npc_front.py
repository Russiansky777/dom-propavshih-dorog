#!/usr/bin/env python3
"""Плоские NPC из листов персонажей: фронтальный вид → game/assets/characters/<id>/front.png.

Для персонажей, у которых ещё нет 3D-фигуры и листов idle/talk (Павел, Митя — BRIEF_CHATGPT_v4 §A, листы
Meshy в assets/incoming/cast_v3/, координатор 22.10: «пока нет 3D-фигур, ставь из них плоские заглушки-NPC»).
Хотспот NPC с полем image рисует картинку по высоте прямоугольника, ногами на его нижней кромке
(RoomBuilder._build_hotspots), — поэтому здесь фигура обрезается по силуэту (alpha ≥ 128) с запасом и
ступни приходятся на нижнюю кромку картинки.

Источник и правка — таблица SOURCES ниже:
  src        — фронтальный вид (один вид на файл);
  sole_y     — строка подошв (ниже — постамент/тень генератора, отрезается);
  keep_x     — [x0, x1]: в полосе strip_y..sole_y оставить только эти столбцы (края постамента у ступней).
Повторный запуск с теми же исходниками даёт тот же файл; --check сверяет без записи (код 1 — расходятся).
Нужен Pillow. Запуск: python3 tools/import_npc_front.py [--check]
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "assets" / "characters"

SOURCES = {
    # Павел, лист pavel_v2 — вид спереди на постаменте (переделка без постамента — у координатора).
    "pavel": {"src": "assets/incoming/cast_v3/pavel_v2.png", "sole_y": 532, "strip_y": 519, "keep_x": [124, 252]},
    # Митя, лист mitya_v1 — вид спереди, без постамента.
    "mitya": {"src": "assets/incoming/cast_v3/mitya_v1.png", "sole_y": 573},
    # Блок 3 (22.10): Ольховка — Нина 67, Илья 32, Ульяна 8, жена Ильи, управляющий; листы cast_v3 без постамента.
    # Заглушки до листов 3D (assets/characters/<имя>/ — коммиты pipeline-bot); тогда фигура — NpcActor по
    # game/data/actors/<имя>.json, эта картинка не показывается.
    "nina": {"src": "assets/incoming/cast_v3/nina_v1.png", "sole_y": 571},
    "ilya": {"src": "assets/incoming/cast_v3/ilya_v1.png", "sole_y": 579},
    "ulyana": {"src": "assets/incoming/cast_v3/ulyana_v1.png", "sole_y": 560},
    "ilya_wife": {"src": "assets/incoming/cast_v3/ilya_wife_v1.png", "sole_y": 550},
    "manager": {"src": "assets/incoming/cast_v3/manager_v1.png", "sole_y": 604},
}
PAD = 4
ALPHA_MIN = 128


def build(spec: dict) -> Image.Image:
    im = Image.open(ROOT / spec["src"]).convert("RGBA")
    w, h = im.size
    sole = min(int(spec["sole_y"]), h - 1)
    px = im.load()
    for y in range(sole + 1, h):
        for x in range(w):
            px[x, y] = (0, 0, 0, 0)
    if "keep_x" in spec:
        x0, x1 = spec["keep_x"]
        for y in range(int(spec.get("strip_y", sole)), sole + 1):
            for x in range(w):
                if x < x0 or x > x1:
                    px[x, y] = (0, 0, 0, 0)
    a = im.getchannel("A").point(lambda v: 255 if v >= ALPHA_MIN else 0)
    box = a.getbbox()
    if box is None:
        raise SystemExit(f"{spec['src']}: пустой силуэт")
    left, top, right, _bottom = box
    crop = im.crop((max(left - PAD, 0), max(top - PAD, 0), min(right + PAD, w), sole + 1))
    return crop


def main() -> int:
    check = "--check" in sys.argv
    bad = 0
    for cid, spec in SOURCES.items():
        im = build(spec)
        target = OUT / cid / "front.png"
        if check:
            same = target.exists() and ImageChops.difference(Image.open(target).convert("RGBA"), im).getbbox() is None
            print(f"{'OK  ' if same else 'DIFF'} {target.relative_to(ROOT)} ← {spec['src']}")
            bad += 0 if same else 1
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            im.save(target, optimize=True)
            print(f"wrote {target.relative_to(ROOT)} {im.size[0]}x{im.size[1]} ← {spec['src']}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
