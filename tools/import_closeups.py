#!/usr/bin/env python3
"""Крупные планы предметов в игру: assets/incoming/<имя>.png → game/assets/closeups/<имя>.png.

Партия 2 брифа v4 (ChatGPT, 22.10, assets/incoming/_meta_p2/README_RU.txt): closeup_bridge_photo, closeup_ilya_drawing,
closeup_plan — 1672×941, лист на столе. В игре они показываются в крупном плане учительского ящика O1
(data/story/rooms/O1.json → teacher_drawer.view: pictures — снимок и рисунок, papers — план с текстом игры поверх
свободной зоны листа). Копия уменьшается до ширины, в которой её рисует крупный план (WIDTH ниже, ×1,2 на чёткость),
пропорции и кадр не меняются — координаты зоны текста плана (text_rect) остаются в пикселях исходника 1672×941.
Импорт Godot — с потерями (compress/mode=1 в .import): это иллюстрации, а не пиксельная графика.

Партия 3 (день второй, 22.10, assets/incoming/_meta_p3/README_RU.txt): крупные планы механик дня второго —
контора в зеркале (M3_view_*), горница Нины с ходиками (O3_*), плита (closeup_plate*), фонарь (closeup_lantern_*),
фото в сенях (closeup_office_photo). Все на одном холсте 1672×941, слои ставятся в (0, 0) — поэтому без
уменьшения (оси стрелок, контур стекла, кольцо плиты — в пикселях холста, data/story/rooms/*.json → mechanic),
прозрачность слоёв сохраняется.
assets/ не трогаем (зона Codex), пишем только копию игры.

Запуск: python3 tools/import_closeups.py           — записать копии
        python3 tools/import_closeups.py --check   — копии есть и совпадают по размеру с тем, что дал бы импорт
        python3 tools/import_closeups.py <имя> …   — только эти (без .png), остальные копии не трогаются
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "incoming"
DST = ROOT / "game" / "assets" / "closeups"
WIDTH = {"closeup_bridge_photo": 840, "closeup_ilya_drawing": 840, "closeup_plan": 1440}
DAY2 = ["M3_view_bg", "M3_view_light", "M3_view_hook", "M3_view_bar_down",
        "O3_bg", "O3_clock_face", "O3_clock_pendulum", "O3_clock_hand_min", "O3_clock_hand_hour", "O3_candle_flame",
        "closeup_plate", "closeup_plate_skoba", "closeup_plate_rope",
        "closeup_lantern_closed", "closeup_lantern_open", "closeup_office_photo"]
WIDTH.update({n: 1672 for n in DAY2})
# Блоки 3–5 (партии 4–6, 22.10, assets/incoming/_meta_p46/README_RU.txt): тетради Евдокии (текст игры — в чистой части
# страницы: data/story/rooms/O3.json → notebooks.view.pages, координаты в пикселях исходника 1672×941), письма Нины,
# зарубки роста, конверт с прежним адресом, рукав пальто, вывеска «Ольховая улица», дощечка Мити — крупные планы
# хотспотов; кадр торца бревна — фон кадра эпилога EP_beam (data/story/rooms/EP_beam.json). Ширина 1440 —
# крупный план рисуется не шире 1600 px экрана.
BLOCK3 = ["closeup_notebook_rule", "closeup_notebook_paths", "closeup_notebook_stopper", "closeup_notebook_bridge",
          "closeup_nina_letters", "closeup_height_notches", "closeup_envelope", "closeup_sleeve",
          "closeup_street_sign", "closeup_mitya_board"]
WIDTH.update({n: 1440 for n in BLOCK3})
# Партия 8б (Q02 «На карте вырос сад», Q06 «Второй верстак», Директор 23.10 11:51): карта Ольховки и слой кальки на
# одном холсте 1672×941 (data/story/rooms/O1.json → village_map.mechanic.art), второй верстак Ильи
# (O4.json → ilya_workshop.mechanic.art) — без уменьшения: слои ставятся в (0, 0), линии кальки — по её прозрачности.
# Пока файлов нет (заявки Q02_closeup_map, Q06_closeup_bench — requested), крупные планы рисует заглушка движка (stub);
# недоставленный файл пропускается.
BATCH8B = ["closeup_village_map_old", "closeup_village_map_tracing", "closeup_second_bench"]
WIDTH.update({n: 1672 for n in BATCH8B})
# Партия 8 (23.10): крупный план доски «Распорядок смен» (data/story/rooms/M1.json → schedule.view: картинка во весь кадр,
# слова игры — поверх листа) и крупные планы 11 предметов для «Рассмотреть» (items.json → examine.art).
BATCH8 = ["M1_schedule_closeup", "closeup_key_house", "closeup_door_hinges", "closeup_brace_plate", "closeup_chalk",
          "closeup_mitten", "closeup_bell_clapper", "closeup_key_sluice", "closeup_clamp", "closeup_school_ribbon",
          "closeup_journal_manager", "closeup_pocket_watch"]
WIDTH.update({n: 1440 for n in BATCH8})   # предмет «Рассмотреть» рисуется не шире ≈ 1320 px экрана
WIDTH["M1_schedule_closeup"] = 1672           # доска во весь кадр (1584 px экрана)


def target_size(w: int, h: int, name: str) -> tuple[int, int]:
    tw = min(w, WIDTH[name])
    return tw, round(h * tw / w)


def main() -> int:
    from PIL import Image
    check = "--check" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    DST.mkdir(parents=True, exist_ok=True)
    bad = 0
    for name in WIDTH:
        if only and name not in only:
            continue
        if not (SRC / f"{name}.png").exists() and name in BATCH8B:
            print(f"wait assets/incoming/{name}.png — ещё не доставлен (в игре заглушка движка)")
            continue
        im = Image.open(SRC / f"{name}.png")
        im = im.convert("RGBA" if im.mode in ("RGBA", "LA") else "RGB")
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
