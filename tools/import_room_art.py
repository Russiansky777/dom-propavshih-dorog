#!/usr/bin/env python3
"""Импорт арта комнаты в игру по данным: data/story/rooms/<LOC>.json → game/assets/rooms/<LOC>/.

Поле комнаты `art_source`:
  {"files": {"bg.png": "assets/incoming/Z4_bg.png", ...},  — куда (в game/assets/rooms/<LOC>/) и откуда
   "canvas": [1672, 941],     — холст фона: слой уже холста дополняется прозрачным справа/снизу
                                 (иначе после отражения он сдвинется на недостающие пиксели)
   "own_size": ["wheel.png"], — файлы со своим размером (отдельный спрайт, не слой холста: колесо M1 1024×1024)
   "alpha_min": 9,            — пиксели с alpha < alpha_min обнуляются (цветной мусор генератора)
   "mirror_x": true,          — отразить по горизонтали (решение Директора: Z4 зеркально, чтобы
                                 боковое крыльцо было справа — продолжение дома с улицы Z2)
   "retouch": {"bg.png": "tools/retouch/F_hug_pelageya.py"}}  — правка дефекта генератора (функция retouch(im))
Файл, которого ещё нет в assets/incoming (арт заказан — слой с `pending`, партия 8б), пропускается: в игре до него
заглушка движка (stub), после доставки тот же запуск кладёт картинку на место заглушки.
Оригиналы в assets/incoming не меняются. Повторный импорт без mirror_x вернул бы неотражённую
картинку при отражённых данных — поэтому отражение записано в данных, а не сделано руками.

Запуск: python3 tools/import_room_art.py Z4          — записать копии
        python3 tools/import_room_art.py Z4 --check  — сверить копии с тем, что дал бы импорт (код 1 — расходятся)
Нужен Pillow (не входит в CI: копии лежат в репозитории).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent


def build(src: Path, canvas: tuple[int, int] | None, alpha_min: int, mirror: bool) -> Image.Image:
    im = Image.open(src)
    has_alpha = im.mode in ("RGBA", "LA") or "transparency" in im.info
    im = im.convert("RGBA" if has_alpha else "RGB")
    if canvas and im.size != tuple(canvas):
        if im.size[0] > canvas[0] or im.size[1] > canvas[1]:
            raise SystemExit(f"{src}: {im.size} больше холста {canvas}")
        padded = Image.new(im.mode, tuple(canvas), (0, 0, 0, 0) if has_alpha else (0, 0, 0))
        padded.paste(im, (0, 0))
        im = padded
    if has_alpha and alpha_min > 0:
        r, g, b, a = im.split()
        keep = a.point(lambda v: 255 if v >= alpha_min else 0)
        a = ImageChops.multiply(a, keep)
        rgb = Image.merge("RGB", (r, g, b))
        black = Image.new("RGB", im.size, (0, 0, 0))
        rgb = Image.composite(rgb, black, keep)
        im = Image.merge("RGBA", (*rgb.split(), a))
    if mirror:
        im = im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return im


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    loc = sys.argv[1]
    check = "--check" in sys.argv
    room = json.loads((ROOT / "data" / "story" / "rooms" / f"{loc}.json").read_text(encoding="utf-8"))
    spec = room.get("art_source")
    if not spec:
        print(f"{loc}: в данных комнаты нет art_source")
        return 2
    out_dir = ROOT / "game" / "assets" / "rooms" / loc
    out_dir.mkdir(parents=True, exist_ok=True)
    canvas = tuple(spec["canvas"]) if "canvas" in spec else None
    bad = 0
    for dst, src in spec["files"].items():
        if not (ROOT / src).exists():
            # Арт заказан и ещё не доставлен (слой с `pending`, заявка assets/manifest.json): в игре до него заглушка
            # движка; как только файл ляжет в assets/incoming, этот же запуск положит его в игру.
            print(f"wait {src} — ещё не доставлен (в игре заглушка движка)")
            continue
        im = build(ROOT / src, None if dst in spec.get("own_size", []) else canvas, int(spec.get("alpha_min", 0)), bool(spec.get("mirror_x", False)))
        # `retouch` {файл: модуль tools/retouch/<имя>.py с retouch(im) -> im}: правка дефекта генератора поверх
        # оригинала (K, 31.10: третий сапог Пелагеи в F_hug_pelageya) — повторный импорт даёт ту же правленую копию
        rt = spec.get("retouch", {}).get(dst)
        if rt:
            import importlib.util
            sp = importlib.util.spec_from_file_location("retouch_mod", ROOT / rt)
            mod = importlib.util.module_from_spec(sp)
            sp.loader.exec_module(mod)
            im = mod.retouch(im)
        target = out_dir / dst
        if check:
            same = target.exists() and ImageChops.difference(Image.open(target).convert(im.mode), im).getbbox() is None
            print(f"{'OK  ' if same else 'DIFF'} {target.relative_to(ROOT)} ← {src}")
            bad += 0 if same else 1
        else:
            im.save(target, optimize=True)
            print(f"wrote {target.relative_to(ROOT)} {im.size[0]}x{im.size[1]} ← {src}"
                  f"{' (mirror_x)' if spec.get('mirror_x') else ''}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
