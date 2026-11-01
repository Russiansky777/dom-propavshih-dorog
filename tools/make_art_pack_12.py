#!/usr/bin/env python3
"""Партия 12 для ChatGPT (по прохождению Директора 31.10): мамино зеркало на верстаке крупно (стр. 33), полка Тихона шире
(стр. 25, 113), три позы Тихона на кресле (стр. 25), канат сквозь кольцо (стр. 106), вода ниже после спуска пруда
(стр. 100), правки плана Заречья (стр. 10). Текст заказа и рамки уже лежат в Docs/art_pack_12 (сделаны 01.11); этот
скрипт собирает архив с основами в полном размере.

Запуск из корня репозитория:
    python3 tools/make_art_pack_12.py   # build/gpt-pack-12/bases + build/gpt-pack-12/Партия_12_для_ChatGPT.zip
"""
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs" / "art_pack_12"
BUILD = ROOT / "build" / "gpt-pack-12"
BASES = BUILD / "bases"
ZIP = BUILD / "Партия_12_для_ChatGPT.zip"
TEXT_NAME = "00_ТЕКСТ_для_ChatGPT.txt"

BASE_FILES = {
    "H2_bg.png": "game/assets/rooms/H2/bg.png",
    "H2_state_bundle_old.png": "game/assets/rooms/H2/state_bundle.png",
    "H2_state_nina_mirror_old.png": "game/assets/rooms/H2/state_nina_mirror.png",
    "H1_bg.png": "game/assets/rooms/H1/bg.png",
    "H1_state_shelf_A_old.png": "game/assets/rooms/H1/state_shelf_A.png",
    "H1_state_holes_stove_old.png": "game/assets/rooms/H1/state_holes_stove.png",
    "H1_fg_chair_arm.png": "game/assets/rooms/H1/fg_chair_arm.png",
    "Tikhon_sheet.png": "assets/reference/tikhon_sheet.png",
    "R2_bg.png": "game/assets/rooms/R2/bg.png",
    "R2_fg_rope_old.png": "game/assets/rooms/R2/fg_rope.png",
    "M1_bg.png": "game/assets/rooms/M1/bg.png",
    "M1_water_still.png": "game/assets/rooms/M1/water_still.png",
    "M1_wheel.png": "game/assets/rooms/M1/wheel.png",
    "M4_bg.png": "game/assets/rooms/M4/bg.png",
    "zarechye_plan.png": "game/assets/ui/map/zarechye_plan.png",
    "zarechye_plan_overlay.png": "game/assets/ui/map/zarechye_plan_overlay.png",
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
