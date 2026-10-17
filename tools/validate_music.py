#!/usr/bin/env python3
"""Проверка фоновой музыки data/story/music.json (MusicDirector, game/scripts/audio/music_director.gd).

Проверяет:
  1. themes: у каждой темы есть file, loop (bool), volume_db (−30..+6); файл есть в assets/music
     (поставка конвейера) и его копия в game/assets/music побайтно совпадает (tools/sync_music.sh);
     у копии есть .import с loop=false (цикл делает директор кроссфейдом, не поток);
  2. rooms: у каждой локации из locations.json есть тема; ключи — известные локации; темы существуют;
     комнаты in_scope (rooms/_index.json) — тоже с темой;
  3. events: ключ — scene:<id> реальной сцены (scenes/E*.json или quests.json); тема существует;
     until ∈ scene_end | track_end и согласован с loop темы (цикличная — scene_end, иначе бесконечна;
     нецикличная — track_end); ключи на «_» — комментарии; голый флаг или другой префикс — ошибка;
  4. duck_except — существующие темы; crossfade_s ∈ (0, 10], loop_crossfade_s ∈ (0, 15],
     end_fade_s ∈ [0, 10], duck_dialogue_db ∈ [−30, 0];
  5. если есть ffprobe — длительность каждого трека больше 2 × loop_crossfade_s (цикл не съедает трек).
Самопроверка (каждый запуск): испорченные копии данных — сцена, которой нет; голый флаг вместо
scene:<id>; комната без темы; цикличная тема до track_end; неизвестная тема — должны дать ошибку.
Код 0 — ошибок нет. Запуск: python3 tools/validate_music.py [--quiet]
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
SRC_DIR = ROOT / "assets" / "music"
GAME_DIR = ROOT / "game" / "assets" / "music"
UNTIL = ("scene_end", "track_end")

errors: list[str] = []
notes: list[str] = []


def err(m: str) -> None:
    errors.append(m)


def load(path: Path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def is_num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def scene_ids() -> set[str]:
    ids: set[str] = set()
    for ep in sorted((STORY / "scenes").glob("E*.json")):
        ids |= {sc["id"] for sc in load(ep)["scenes"]}
    ids |= {q["id"] for q in load(STORY / "quests.json")["quests"]}
    return ids


def duration_s(path: Path) -> float | None:
    if shutil.which("ffprobe") is None:
        return None
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                       capture_output=True, text=True)
    try:
        return float(r.stdout.strip())
    except ValueError:
        return None


def check(data: dict, files: bool = True) -> None:
    """Fills `errors`/`notes` for one music.json document; files=False skips the file checks."""
    themes: dict = data.get("themes", {})
    if not isinstance(themes, dict) or not themes:
        err("themes: нет ни одной темы")
        themes = {}
    loop_xf = data.get("loop_crossfade_s")

    # 1. Themes and files.
    for tid, th in themes.items():
        ctx = f"themes.{tid}"
        if not isinstance(th, dict):
            err(f"{ctx}: ожидается объект")
            continue
        if not isinstance(th.get("loop"), bool):
            err(f"{ctx}.loop: ожидается true/false")
        vol = th.get("volume_db", 0.0)
        if not (is_num(vol) and -30.0 <= vol <= 6.0):
            err(f"{ctx}.volume_db {vol!r} вне −30..+6")
        fname = th.get("file")
        if not isinstance(fname, str) or not fname.endswith(".ogg"):
            err(f"{ctx}.file: ожидается имя .ogg, получено {fname!r}")
            continue
        if not files:
            continue
        src, dst = SRC_DIR / fname, GAME_DIR / fname
        if not src.is_file():
            err(f"{ctx}: нет файла assets/music/{fname}")
        if not dst.is_file():
            err(f"{ctx}: нет копии game/assets/music/{fname} (tools/sync_music.sh)")
        elif src.is_file() and src.read_bytes() != dst.read_bytes():
            err(f"{ctx}: game/assets/music/{fname} отличается от assets/music (tools/sync_music.sh)")
        imp = GAME_DIR / (fname + ".import")
        if dst.is_file():
            if not imp.is_file():
                err(f"{ctx}: нет {imp.relative_to(ROOT)} (импорт с loop=false — tools/sync_music.sh)")
            elif "loop=false" not in imp.read_text(encoding="utf-8").splitlines():
                err(f"{ctx}: {imp.relative_to(ROOT)} без loop=false — поток не должен зацикливаться сам")
        d = duration_s(src) if src.is_file() else None
        if d is not None:
            notes.append(f"{tid}: {fname} {d:.1f} с, loop={th.get('loop')}, {vol:+.1f} dB")
            if is_num(loop_xf) and d <= 2 * loop_xf:
                err(f"{ctx}: трек {d:.1f} с короче 2 × loop_crossfade_s")

    # 2. Rooms.
    locations = [loc["id"] for loc in load(STORY / "locations.json")["locations"]]
    rooms: dict = data.get("rooms", {})
    for rid in locations:
        if rid not in rooms:
            err(f"rooms: у локации {rid} нет темы")
    for rid, tid in rooms.items():
        if rid not in locations:
            err(f"rooms.{rid}: нет такой локации в locations.json")
        if tid not in themes:
            err(f"rooms.{rid}: неизвестная тема {tid!r}")
    index = load(STORY / "rooms" / "_index.json")
    for rid in index.get("in_scope", []):
        if rid not in rooms:
            err(f"rooms: у комнаты in_scope {rid} нет темы")

    # 3. Events.
    scenes = scene_ids()
    flags = set(load(STORY / "flags.json")["flags"].keys())
    events: dict = data.get("events", {})
    for key, val in events.items():
        if key.startswith("_"):
            continue
        ctx = f"events.{key}"
        if not key.startswith("scene:"):
            what = "флаг из flags.json" if key in flags else "неизвестный ключ"
            err(f"{ctx}: {what} — поддерживаются только ключи scene:<id>")
            continue
        sid = key[len("scene:"):]
        if sid not in scenes:
            err(f"{ctx}: нет сцены {sid!r} в scenes/*.json и quests.json")
        if isinstance(val, str):
            tid, until = val, None
        elif isinstance(val, dict):
            tid, until = val.get("theme"), val.get("until")
            extra = set(val) - {"theme", "until"}
            if extra:
                err(f"{ctx}: лишние поля {sorted(extra)}")
        else:
            err(f"{ctx}: ожидается тема или {{theme, until}}")
            continue
        if tid not in themes:
            err(f"{ctx}: неизвестная тема {tid!r}")
            continue
        loops = bool(themes[tid].get("loop", True))
        if until is None:
            until = "scene_end" if loops else "track_end"
        if until not in UNTIL:
            err(f"{ctx}.until {until!r}: ожидается одно из {UNTIL}")
        elif loops and until == "track_end":
            err(f"{ctx}: цикличная тема {tid} с until=track_end никогда не закончится")
        elif not loops and until == "scene_end":
            err(f"{ctx}: нецикличная тема {tid} должна дослушиваться (until=track_end)")
        notes.append(f"{key} → {tid} до {until}")

    # 4. Parameters.
    for tid in data.get("duck_except", []):
        if tid not in themes:
            err(f"duck_except: неизвестная тема {tid!r}")
    ranges = {"crossfade_s": (0.0, 10.0, False), "loop_crossfade_s": (0.0, 15.0, False),
              "end_fade_s": (0.0, 10.0, True), "duck_dialogue_db": (-30.0, 0.0, True)}
    for k, (lo, hi, lo_incl) in ranges.items():
        v = data.get(k)
        if v is None and k == "end_fade_s":
            continue
        if not is_num(v) or not ((lo <= v) if lo_incl else (lo < v)) or v > hi:
            err(f"{k} {v!r} вне {'[' if lo_incl else '('}{lo}, {hi}]")


def selftest(data: dict) -> list[str]:
    """Broken copies of the data must each be rejected; returns the variants that slipped through."""
    import copy
    def broken_scene(d): d["events"]["scene:M99"] = "mirror"
    def bare_flag(d): d["events"]["mirror_mill_mounted"] = "mirror"
    def room_missing(d): d["rooms"].pop("H1", None)
    def loop_track_end(d): d["events"]["scene:M10"] = {"theme": "mirror", "until": "track_end"}
    def unknown_theme(d): d["rooms"]["Z1"] = "storm"
    missed: list[str] = []
    for fn in (broken_scene, bare_flag, room_missing, loop_track_end, unknown_theme):
        d = copy.deepcopy(data)
        fn(d)
        errors.clear()
        check(d, files=False)
        if not errors:
            missed.append(fn.__name__)
    errors.clear()
    notes.clear()
    return missed


def main() -> int:
    quiet = "--quiet" in sys.argv
    path = STORY / "music.json"
    if not path.exists():
        print("[music] нет data/story/music.json")
        return 1
    try:
        data = load(path)
    except json.JSONDecodeError as ex:
        print(f"ERROR music.json: не JSON: {ex}")
        return 1
    missed = selftest(data)
    check(data)
    for m in missed:
        err(f"самопроверка: испорченный вариант «{m}» не дал ошибки")
    themes: dict = data.get("themes", {})
    rooms: dict = data.get("rooms", {})
    events: dict = data.get("events", {})
    if not quiet:
        for n in notes:
            print("  " + n)
    for e in errors:
        print("ERROR " + e)
    n_events = len([k for k in events if not k.startswith("_")])
    print(f"[music] {'OK' if not errors else 'FAIL'}: {len(themes)} тем, {len(rooms)} комнат, {n_events} событий, {len(errors)} ошибок")
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
