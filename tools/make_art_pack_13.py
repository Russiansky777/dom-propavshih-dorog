#!/usr/bin/env python3
"""Партия 13 для ChatGPT (по партии 12 и приёмке K, 01.11): кадры рта Тихона в позе «калачиком» и та же широкая полка,
лежащая на лежанке, что потом вешается у печи. Текст и рамки — Docs/art_pack_13; этот скрипт собирает архив с основами.

    python3 tools/make_art_pack_13.py   # build/gpt-pack-13/Партия_13_для_ChatGPT.zip
"""
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs" / "art_pack_13"
BUILD = ROOT / "build" / "gpt-pack-13"
BASES = BUILD / "bases"
ZIP = BUILD / "Партия_13_для_ChatGPT.zip"
TEXT_NAME = "00_ТЕКСТ_для_ChatGPT.txt"

BASE_FILES = {
    "Tikhon_pose_loaf.png": "game/assets/characters/tikhon/tikhon_loaf.png",
    "old_mouth_1.png": "game/assets/characters/tikhon/mouth_1.png",
    "old_mouth_2.png": "game/assets/characters/tikhon/mouth_2.png",
    "old_mouth_3.png": "game/assets/characters/tikhon/mouth_3.png",
    "Tikhon_sheet.png": "assets/reference/tikhon_sheet.png",
    "H1_bg.png": "game/assets/rooms/H1/bg.png",
    "H1_state_bench_wide_shelf_old.png": "game/assets/rooms/H1/state_bench_wide_shelf.png",
    "H1_state_bench_wide_scarf_old.png": "game/assets/rooms/H1/state_bench_wide_scarf.png",
    "H1_state_bench_wide_bare.png": "game/assets/rooms/H1/state_bench_wide_bare.png",
    "H1_state_shelf_A_wide_hung.png": "game/assets/rooms/H1/state_shelf_A.png",
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
