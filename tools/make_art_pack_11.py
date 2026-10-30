#!/usr/bin/env python3
"""Партия 11 для ChatGPT (сверка 30.10): лежанка у печи шире (Директор 29.10 стр. 60–61) — три состояния, и торец бревна
с вырезанным «Агата» (25.10 стр. 165; сейчас в игре — резьба, нарисованная кодом, tools/make_beam_cut.py).

Запуск из корня репозитория:
    python3 tools/make_art_pack_11.py   # Docs/art_pack_11 (текст, кропы) + build/gpt-pack-11 (основы, zip)

Прямоугольники — [x1, y1, x2, y2) в пикселях основы 1672×941 (x2, y2 не входят). Слои — полный холст, (0,0), 1:1.
"""
import shutil
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs" / "art_pack_11"
BUILD = ROOT / "build" / "gpt-pack-11"
BASES = BUILD / "bases"
ZIP = BUILD / "Партия_11_для_ChatGPT.zip"
TEXT_NAME = "00_ТЕКСТ_для_ChatGPT.txt"

BENCH = [360, 462, 712, 684]     # новая лежанка вместе с тем, что на ней (было [378, 480, 700, 640))
BENCH_FREE = [372, 470, 480, 560]  # левый конец у печи свободен: здесь в день 3 сидит Тихон
BEAM = [520, 362, 872, 540]      # надпись на торце (у «Дуня» было [540, 380, 850, 522))

BASE_FILES = {
    "H1_bg.png": "game/assets/rooms/H1/bg.png",
    "H1_fg_table_chair.png": "game/assets/rooms/H1/fg_table_chair.png",
    "H1_fg_chair_arm.png": "game/assets/rooms/H1/fg_chair_arm.png",
    "H1_state_scarf_over_shelf_old.png": "assets/incoming/H1_state_scarf_over_shelf.png",
    "H1_state_bench_bare_old.png": "assets/incoming/H1_state_bench_bare.png",
    "H1_state_shelf_on_bench_old.png": "assets/incoming/H1_state_shelf_on_bench.png",
    "EP_beam_bg.png": "assets/incoming/EP_beam_bg.png",
    "EP_beam_cut_dunya_STYLE.png": "assets/incoming/EP_beam_cut_dunya.png",
}

TEXT = f"""ДОМ ПРОПАВШИХ ДОРОГ — ПАРТИЯ 11 (30 октября 2026)
Два заказа. Стиль — как у всех комнат игры: тёплая живопись, мягкий свет, фактура дерева и побелки; тот же свет и та же
перспектива, что на основе. Все новые файлы — PNG 1672×941, RGBA, полный холст: положим в игру в точку (0,0), масштаб 1:1.
Вне указанного прямоугольника альфа строго 0. Координаты — [x1, y1, x2, y2), от левого верхнего угла холста.

=== 1. ЛЕЖАНКА У ПЕЧИ ШИРЕ (жилая комната H1) ===
Основа: bases/H1_bg.png. Сейчас у печи узкая лавка (x 378–700, y 480–640) — на неё Агата ложится спать, значит это
лежанка, а не лавка: нужна шире (глубже к зрителю), как спальная лежанка у русской печи — широкие доски, может быть
сложенное лоскутное одеяло или войлок у стены. Длина та же, вдоль печи. Ножки и тень на пол — как на основе.
Новый прямоугольник всех трёх слоёв: {BENCH} (захватите кусок пола и стены вокруг, чтобы стык был незаметен; внутри
прямоугольника слой непрозрачен). Левый конец у печи {BENCH_FREE} оставьте свободным (там потом сидит кот Тихон),
на нём ничего не лежит.
Поверх лежанки в игре лежат передние предметы: bases/H1_fg_table_chair.png и bases/H1_fg_chair_arm.png (кресло и
столик) — их рисовать не нужно, но под ними лежанка должна продолжаться.
Три файла — одна и та же лежанка, разные предметы на ней (как в старых слоях, они в bases/ с пометкой _old):
  1a. H1_state_bench_wide_scarf.png — на лежанке снятая с печи деревянная полка, поверх неё мокрый полосатый
      платок (как в H1_state_scarf_over_shelf_old.png).
  1b. H1_state_bench_wide_shelf.png — на лежанке только полка, без платка (как bench_bare_old + shelf_on_bench_old).
  1c. H1_state_bench_wide_bare.png — пустая лежанка.
Полка и платок — правее середины лежанки, левый конец свободен.

=== 2. ТОРЕЦ БРЕВНА С НАДПИСЬЮ «Агата» (эпилог EP_beam) ===
Основа: bases/EP_beam_bg.png. Стиль надписи — точно как в bases/EP_beam_cut_dunya_STYLE.png: вырезано ножом по
торцу, буквы той же высоты и того же почерка, с тёмной канавкой и светлой кромкой, свет сверху слева.
Слово: Агата (с заглавной, одно слово). Прямоугольник: {BEAM}, по центру торца, как «Дуня».
Файл: 2. EP_beam_cut_agata.png — прозрачный везде, кроме резьбы (полупрозрачные края резьбы — можно).

ЧТО ПРИСЛАТЬ: 4 PNG с этими именами + по JPEG-превью «основа + слой». Если пришлось сдвинуть прямоугольник — напишите.
"""


def frame(src: str, rect, out: Path, extra=None, crop_pad=120):
    im = Image.open(ROOT / src).convert("RGB")
    d = ImageDraw.Draw(im)
    d.rectangle([rect[0], rect[1], rect[2] - 1, rect[3] - 1], outline=(255, 40, 40), width=3)
    if extra:
        d.rectangle([extra[0], extra[1], extra[2] - 1, extra[3] - 1], outline=(40, 200, 255), width=3)
    x1, y1 = max(0, rect[0] - crop_pad), max(0, rect[1] - crop_pad)
    x2, y2 = min(im.width, rect[2] + crop_pad), min(im.height, rect[3] + crop_pad)
    im.crop((x1, y1, x2, y2)).save(out, quality=90)


def main() -> int:
    DOCS.mkdir(parents=True, exist_ok=True)
    BASES.mkdir(parents=True, exist_ok=True)
    (DOCS / TEXT_NAME).write_text(TEXT, encoding="utf-8")
    for name, src in BASE_FILES.items():
        shutil.copy(ROOT / src, BASES / name)
    frame("game/assets/rooms/H1/bg.png", BENCH, DOCS / "1_лежанка_рамка.jpg", BENCH_FREE)
    frame("assets/incoming/EP_beam_bg.png", BEAM, DOCS / "2_торец_рамка.jpg")
    # the current look of the scarf state over the background (what is being replaced)
    bg = Image.open(ROOT / "game/assets/rooms/H1/bg.png").convert("RGBA")
    bg.alpha_composite(Image.open(ROOT / "assets/incoming/H1_state_scarf_over_shelf.png").convert("RGBA"))
    bg.convert("RGB").crop((BENCH[0] - 120, BENCH[1] - 120, BENCH[2] + 120, BENCH[3] + 120)).save(DOCS / "1_лежанка_сейчас.jpg", quality=90)
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(DOCS / TEXT_NAME, TEXT_NAME)
        for f in sorted(DOCS.glob("*.jpg")):
            z.write(f, f.name)
        for f in sorted(BASES.glob("*.png")):
            z.write(f, "bases/" + f.name)
    print(ZIP.relative_to(ROOT), round(ZIP.stat().st_size / 1e6, 1), "MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
