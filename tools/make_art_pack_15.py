#!/usr/bin/env python3
"""Партия 15 для ChatGPT (01.11, прохождение Директора стр. 48–49): нарисованный горящий фонарь у ног Мити на дальней
опоре R3 (вместо вырезки из крупного плана) и правка рыжего пятна у кольца на канате R2 (v3 → v4). Текст и образцы —
Docs/art_pack_15; этот скрипт собирает архив с основами.

    python3 tools/make_art_pack_15.py   # build/gpt-pack-15/Партия_15_для_ChatGPT.zip (+ копия в ZIP_COPY, если задан)
"""
import os
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs" / "art_pack_15"
BUILD = ROOT / "build" / "gpt-pack-15"
BASES = BUILD / "bases"
ZIP = BUILD / "Партия_15_для_ChatGPT.zip"
TEXT_NAME = "00_ТЕКСТ_для_ChatGPT.txt"

BASE_FILES = {
    "R3_bg.png": "game/assets/rooms/R3/bg.png",
    "R3_state_mitya_lantern_vremenno.png": "game/assets/rooms/R3/state_mitya_lantern.png",
    "closeup_lantern_closed.png": "game/assets/closeups/closeup_lantern_closed.png",
    "R2_fg_rope_v3.png": "assets/incoming/R2_fg_rope_v3.png",
    "R2_bg.png": "game/assets/rooms/R2/bg.png",
}


def main() -> int:
    BASES.mkdir(parents=True, exist_ok=True)
    for name, src in BASE_FILES.items():
        shutil.copy(ROOT / src, BASES / name)
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(DOCS / TEXT_NAME, TEXT_NAME)
        for f in sorted(DOCS.glob("*.jpg")) + sorted(DOCS.glob("*.png")):
            z.write(f, f.name)
        for f in sorted(BASES.glob("*.png")):
            z.write(f, "bases/" + f.name)
    print(ZIP.relative_to(ROOT), round(ZIP.stat().st_size / 1e6, 1), "MB")
    copy = os.environ.get("ZIP_COPY", "")
    if copy:
        shutil.copy(ZIP, copy)
        print(copy)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
