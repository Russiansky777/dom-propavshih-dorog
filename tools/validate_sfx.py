#!/usr/bin/env python3
"""Проверка звуков data/story/sfx.json (SfxDirector, game/scripts/audio/sfx_director.gd).

Проверяет:
  1. sounds: у каждого звука есть files (≥ 1), все файлы есть в game/assets/sfx и измерены в
     levels.json (tools/prepare_sfx.sh); pitch_jitter ∈ [0, 0.2], volume_jitter_db ∈ [0, 6];
  2. steps: surfaces → существующие звуки; у каждой локации из locations.json есть покрытие;
     areas — известные комнаты, многоугольники ≥ 3 точек, известные покрытия;
  3. doors: ключ «ОТКУДА>КУДА» — известные локации; если у комнаты ОТКУДА есть data/story/rooms/<id>.json,
     в ней есть выход в КУДА; звук существует и это дверь (door_*);
  4. bag: receive/select/deselect (сигнал game_ui.gd bag_sound_requested) → существующие звуки;
  5. loops: файлы есть, импорт loop=true; огонь — комната существует, флаги «if» стоят в «if» огня
     этой комнаты в data/story/lights/<room>.json; дождь — outside ровно комнаты с дождём в
     data/story/ambient (сам файл или его пресет), inside и outside не пересекаются, все — локации;
  6. громкость относительно музыки (музыка — −18 LUFS + volume_db темы, кроме нецикличного финала):
     шаг (максимум momentary + volume_db + разброс) не громче самой тихой темы; дверь громче самой
     громкой темы, но не более чем на 6 dB; дождь снаружи (LUFS integrated + outside_db) — −28 ± 1,5;
     огонь у печи тише самой тихой темы.
Самопроверка (каждый запуск): испорченные копии данных должны дать ошибку.
Код 0 — ошибок нет. Запуск: python3 tools/validate_sfx.py [--quiet]
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
SFX_DIR = ROOT / "game" / "assets" / "sfx"
MUSIC_LUFS = -18.0          # pipeline/audio/prepare_music.sh: every theme is normalised to −18 LUFS
BAG_KINDS = ("receive", "select", "deselect")

errors: list[str] = []
notes: list[str] = []


def err(m: str) -> None:
    errors.append(m)


def load(path: Path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def is_num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def rain_rooms_from_ambient() -> set[str]:
    amb = STORY / "ambient"
    if not amb.is_dir():
        return set()
    presets = load(amb / "_index.json").get("presets", {})
    out = set()
    for f in amb.glob("*.json"):
        if f.name.startswith("_"):
            continue
        d = load(f)
        if "rain" in d or "rain" in presets.get(d.get("preset", ""), {}):
            out.add(d.get("id", f.stem))
    return out


def check(data: dict, ctx_files: bool = True) -> None:
    locations = [loc["id"] for loc in load(STORY / "locations.json")["locations"]]
    levels = load(SFX_DIR / "levels.json") if (SFX_DIR / "levels.json").exists() else {}
    if ctx_files and not levels:
        err("нет game/assets/sfx/levels.json (tools/prepare_sfx.sh)")
    sounds: dict = data.get("sounds", {})

    # 1. Sounds.
    for sid, spec in sounds.items():
        ctx = f"sounds.{sid}"
        files = spec.get("files", [])
        if not files:
            err(f"{ctx}: нет файлов")
        for fn in files:
            if ctx_files and not (SFX_DIR / fn).is_file():
                err(f"{ctx}: нет файла game/assets/sfx/{fn}")
            if ctx_files and fn not in levels:
                err(f"{ctx}: {fn} не измерен в levels.json")
        if not (0.0 <= spec.get("pitch_jitter", 0.0) <= 0.2):
            err(f"{ctx}.pitch_jitter вне [0, 0.2]")
        if not (0.0 <= spec.get("volume_jitter_db", 0.0) <= 6.0):
            err(f"{ctx}.volume_jitter_db вне [0, 6]")
        if not is_num(spec.get("volume_db", 0.0)):
            err(f"{ctx}.volume_db не число")

    # 2. Steps.
    st: dict = data.get("steps", {})
    surfaces: dict = st.get("surfaces", {})
    for surf, sid in surfaces.items():
        if sid not in sounds:
            err(f"steps.surfaces.{surf}: нет звука {sid!r}")
    rooms: dict = st.get("rooms", {})
    for rid in locations:
        if rid not in rooms:
            err(f"steps.rooms: у локации {rid} нет покрытия")
    for rid, surf in rooms.items():
        if rid not in locations:
            err(f"steps.rooms.{rid}: нет такой локации")
        if surf not in surfaces:
            err(f"steps.rooms.{rid}: неизвестное покрытие {surf!r}")
    for rid, areas in st.get("areas", {}).items():
        if rid not in locations:
            err(f"steps.areas.{rid}: нет такой локации")
        for i, a in enumerate(areas):
            if a.get("surface") not in surfaces:
                err(f"steps.areas.{rid}[{i}]: неизвестное покрытие {a.get('surface')!r}")
            poly = a.get("poly", [])
            if len(poly) < 3 or not all(isinstance(p, list) and len(p) == 2 and all(is_num(v) for v in p) for p in poly):
                err(f"steps.areas.{rid}[{i}]: многоугольник ≥ 3 точек [x, y]")

    # 3. Doors.
    for key, sid in data.get("doors", {}).items():
        if key.startswith("_"):
            continue
        if ">" not in key:
            err(f"doors.{key}: ключ «ОТКУДА>КУДА»")
            continue
        a, b = key.split(">", 1)
        if a not in locations or b not in locations:
            err(f"doors.{key}: неизвестная локация")
        rf = STORY / "rooms" / f"{a}.json"
        if rf.exists() and b not in [e.get("to") for e in load(rf).get("exits", [])]:
            err(f"doors.{key}: в rooms/{a}.json нет выхода в {b}")
        if sid not in sounds or not str(sid).startswith("door_"):
            err(f"doors.{key}: {sid!r} — не звук двери")

    # 4. Bag.
    bag = data.get("bag", {})
    for kind in BAG_KINDS:
        if bag.get(kind) not in sounds:
            err(f"bag.{kind}: нет звука")

    # 5. Loops.
    loops = data.get("loops", {})
    for lid, lp in loops.items():
        fn = lp.get("file", "")
        if ctx_files:
            if not (SFX_DIR / fn).is_file():
                err(f"loops.{lid}: нет файла game/assets/sfx/{fn}")
            imp = SFX_DIR / (fn + ".import")
            if not imp.is_file() or "loop=true" not in imp.read_text(encoding="utf-8").splitlines():
                err(f"loops.{lid}: {fn}.import без loop=true")
    fire = loops.get("stove_fire")
    if fire:
        room = fire.get("room")
        if room not in locations:
            err(f"loops.stove_fire.room {room!r}: нет такой локации")
        lf = STORY / "lights" / f"{room}.json"
        fire_ifs: set[str] = set()
        if lf.exists():
            for s in load(lf).get("sources", []):
                if s.get("type") == "fire":
                    fire_ifs |= set(s.get("if", []))
        for fl in fire.get("if", []):
            if fl not in fire_ifs:
                err(f"loops.stove_fire.if: флаг {fl!r} не управляет огнём в data/story/lights/{room}.json")
        if not (is_num(fire.get("near_px")) and is_num(fire.get("far_px")) and 0 <= fire["near_px"] < fire["far_px"]):
            err("loops.stove_fire: near_px < far_px")
    rain = loops.get("rain")
    if rain:
        outside, inside = set(rain.get("outside", [])), set(rain.get("inside", []))
        for rid in outside | inside:
            if rid not in locations:
                err(f"loops.rain: нет локации {rid}")
        if outside & inside:
            err(f"loops.rain: и снаружи, и внутри: {sorted(outside & inside)}")
        amb = rain_rooms_from_ambient()
        if amb and outside != amb:
            err(f"loops.rain.outside {sorted(outside)} ≠ комнаты с дождём в data/story/ambient {sorted(amb)}")

    # 6. Loudness against the music.
    if not levels:
        return
    music = load(STORY / "music.json")["themes"]
    looped = [MUSIC_LUFS + float(t.get("volume_db", 0.0)) for t in music.values() if t.get("loop", True)]
    m_min, m_max = min(looped), max(looped)
    def eff(sid: str, key: str = "lufs_m_max") -> float:
        spec = sounds[sid]
        return max(levels[f][key] for f in spec["files"] if f in levels) + float(spec.get("volume_db", 0.0))
    for surf, sid in surfaces.items():
        if sid in sounds and all(f in levels for f in sounds[sid]["files"]):
            e = eff(sid) + float(sounds[sid].get("volume_jitter_db", 0.0))
            notes.append(f"шаги {surf}: до {e:.1f} LUFS (музыка {m_min:.0f}…{m_max:.0f})")
            if e > m_min:
                err(f"шаги {surf}: {e:.1f} LUFS громче музыки ({m_min:.1f})")
    for sid in sorted({v for k, v in data.get("doors", {}).items() if not k.startswith("_")}):
        if sid in sounds and all(f in levels for f in sounds[sid]["files"]):
            e = eff(sid)
            notes.append(f"{sid}: {e:.1f} LUFS")
            if not (m_max < e <= m_max + 6.0):
                err(f"{sid}: {e:.1f} LUFS — дверь должна быть чуть громче музыки ({m_max:.1f} < x ≤ {m_max + 6:.1f})")
    if rain and rain.get("file") in levels:
        e = levels[rain["file"]]["lufs_i"] + float(rain.get("outside_db", 0.0))
        notes.append(f"дождь снаружи: {e:.1f} LUFS, внутри {e + float(rain.get('inside_db', 0.0)):.1f} + ФНЧ {rain.get('inside_lowpass_hz')} Гц")
        if abs(e - -28.0) > 1.5:
            err(f"дождь снаружи {e:.1f} LUFS, ожидается −28 ± 1,5")
        if float(rain.get("inside_db", 0.0)) >= 0.0:
            err("loops.rain.inside_db: внутри должно быть тише, чем снаружи")
    if fire and fire.get("file") in levels:
        e = levels[fire["file"]]["lufs_i"] + float(fire.get("volume_db", 0.0))
        notes.append(f"огонь у печи: {e:.1f} LUFS")
        if e > m_min:
            err(f"огонь у печи {e:.1f} LUFS громче музыки ({m_min:.1f})")


def selftest(data: dict) -> list[str]:
    def unknown_exit(d): d["doors"]["H2>Z3"] = "door_light"
    def steps_too_loud(d): d["sounds"]["steps_gravel"]["volume_db"] = 6.0
    def room_without_surface(d): d["steps"]["rooms"].pop("H1")
    def rain_in_school(d): d["loops"]["rain"]["outside"].append("O1")
    def fire_wrong_flag(d): d["loops"]["stove_fire"]["if"] = ["h1_shutter_open"]
    def door_too_loud(d): d["sounds"]["door_passage"]["volume_db"] = 8.0
    missed: list[str] = []
    for fn in (unknown_exit, steps_too_loud, room_without_surface, rain_in_school, fire_wrong_flag, door_too_loud):
        d = copy.deepcopy(data)
        fn(d)
        errors.clear()
        check(d, ctx_files=False)
        if not errors:
            missed.append(fn.__name__)
    errors.clear()
    notes.clear()
    return missed


def main() -> int:
    quiet = "--quiet" in sys.argv
    path = STORY / "sfx.json"
    if not path.exists():
        print("[sfx] нет data/story/sfx.json")
        return 1
    data = load(path)
    missed = selftest(data)
    check(data)
    for m in missed:
        err(f"самопроверка: испорченный вариант «{m}» не дал ошибки")
    if not quiet:
        for n in notes:
            print("  " + n)
    for e in errors:
        print("ERROR " + e)
    print(f"[sfx] {'OK' if not errors else 'FAIL'}: {len(data.get('sounds', {}))} звуков, "
          f"{len([k for k in data.get('doors', {}) if not k.startswith('_')])} дверей, {len(errors)} ошибок")
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
