#!/usr/bin/env python3
"""Партия 14 для ChatGPT (01.11, Директор: «мультяшный окунь и поплавок»): окунь, поплавок, чашки и ложечка ритма
вместо фигур, которые рисует движок. Текст и образцы — Docs/art_pack_14; этот скрипт собирает архив с основами.

    python3 tools/make_art_pack_14.py   # build/gpt-pack-14/Партия_14_для_ChatGPT.zip
"""
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs" / "art_pack_14"
BUILD = ROOT / "build" / "gpt-pack-14"
BASES = BUILD / "bases"
ZIP = BUILD / "Партия_14_для_ChatGPT.zip"
TEXT_NAME = "00_ТЕКСТ_для_ChatGPT.txt"

BASE_FILES = {
    "R3_bg.png": "game/assets/rooms/R3/bg.png",
    "H1_bg.png": "game/assets/rooms/H1/bg.png",
    "H1_state_cup_table_white.png": "game/assets/rooms/H1/state_cup_table_white.png",
    "H1_state_cup_table_blue.png": "game/assets/rooms/H1/state_cup_table_blue.png",
    "Tikhon_sheet.png": "assets/reference/tikhon_sheet.png",
    "R2_fg_rope_v2.png": "game/assets/rooms/R2/fg_rope.png",
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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
