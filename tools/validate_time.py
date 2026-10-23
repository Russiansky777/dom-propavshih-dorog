#!/usr/bin/env python3
"""Время суток (F17, Директор 23.10: «чтобы времена дня скоординированно со сценарием и логикой сменялись») —
проверка data/story/time/*.json против сценария.

    python3 tools/validate_time.py [--quiet]

Проверяет:
  1. состояния (_index.json → states): id уникальны; дни не убывают; внутри дня фазы идут по порядку
     утро → полдень → после полудня/день → сумерки → вечер → ночь; у каждого состояния строка журнала (ключ
     текста есть); условие when — только флаги, которые основная история ставит и никто не снимает
     (done_<сцена основной истории> или выдача основной сцены); состояние только своей комнаты (room_only)
     без when;
  2. основная история по порядку (сцены E*.json type main, выдачи копятся, как в RoomManager.start_at):
     каждая сцена начинается ровно в одном состоянии — том, что записано в scenes (таблица
     Docs/TIME_OF_DAY.md); время внутри дня не идёт назад, а день не убывает; в scenes нет лишних сцен;
  3. оттенки (grades и grade комнат): ключ — состояние или фаза, значение {tint: «#rrggbb»} или "painted";
     inherit — существующий класс; классы комнат (class) существуют;
  4. файлы комнат: комната есть в rooms/; replaces_effects — эффекты, которые в комнате есть; окна в кадре
     1920×1080, условия if/unless — известные флаги (flags.json, выдачи, автопрефиксы) или виртуальные tod_*;
     fixed_state — существующее состояние;
  5. locals: комнаты существуют, state — состояние room_only.
Самопроверка: перестановка двух состояний одного дня даёт ошибку (иначе проверка порядка не работает).
Код 0 — ошибок нет.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
TIME = STORY / "time"
PHASE_ORDER = {"morning": 0, "midday": 1, "afternoon": 2, "day": 2, "dusk": 3, "evening": 4, "night": 5}
COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
AUTO = ("done_", "has_", "started_", "visited_", "seen_room_", "q0", "q1")

errors: list[str] = []


def err(m: str) -> None:
    errors.append(m)


def load(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))


def main_scenes() -> list[dict]:
    """Сцены основной истории в порядке файлов (как StoryData.scene_order: эпизоды по имени файла)."""
    out = []
    for f in sorted((STORY / "scenes").glob("E*.json")):
        for s in load(f).get("scenes", []):
            if s.get("type") == "main":
                out.append(s)
    return out


def tod_flags(index: dict) -> set[str]:
    names = {"tod_dark"}
    for s in index.get("states", []):
        for n in (s.get("id"), s.get("phase"), f"day{s.get('day', 0)}"):
            if n:
                names.add("tod_" + str(n))
    return names


def state_for(index: dict, flags: set[str]) -> str:
    out = ""
    for s in index.get("states", []):
        if s.get("room_only"):
            continue
        w = s.get("when", {}) or {}
        if all(f in flags for f in w.get("all", [])) and (not w.get("any") or any(f in flags for f in w["any"])):
            out = s["id"]
    return out


def check_states(index: dict, texts: dict, mains: list[dict], tag: str = "") -> None:
    states = index.get("states", [])
    ids = [s.get("id") for s in states]
    if len(ids) != len(set(ids)):
        err(f"{tag}states: повторяются id")
    main_ids = {s["id"] for s in mains}
    granted = set()
    for s in mains:
        granted |= set(s.get("grants", {}).get("flags", []))
    prev_day, prev_phase = 0, -1
    for s in states:
        sid = s.get("id", "?")
        lab = str(s.get("label", ""))
        if not lab.startswith("@") or lab[1:] not in texts:
            err(f"{tag}states.{sid}: нет строки журнала {lab!r} в data/story/text")
        ph = s.get("phase")
        if s.get("room_only"):
            if s.get("when"):
                err(f"{tag}states.{sid}: состояние своей комнаты (room_only) — без when")
            continue
        if ph not in PHASE_ORDER:
            err(f"{tag}states.{sid}: фаза {ph!r} — одна из {', '.join(PHASE_ORDER)}")
            continue
        day = int(s.get("day", 0))
        if day < prev_day:
            err(f"{tag}states.{sid}: день {day} раньше предыдущего {prev_day}")
        if day == prev_day and PHASE_ORDER[ph] < prev_phase:
            err(f"{tag}states.{sid}: в дне {day} фаза «{ph}» идёт после более поздней — время не должно идти назад")
        if day != prev_day:
            prev_phase = -1
        prev_day, prev_phase = day, PHASE_ORDER[ph]
        w = s.get("when", {}) or {}
        for f in list(w.get("all", [])) + list(w.get("any", [])):
            if f.startswith("done_"):
                if f[5:] not in main_ids:
                    err(f"{tag}states.{sid}.when: {f} — нет такой сцены основной истории")
            elif f not in granted:
                err(f"{tag}states.{sid}.when: флаг {f} не выдаёт ни одна основная сцена (время выводится только из основной истории)")


def check_scenes(index: dict, mains: list[dict], tag: str = "") -> None:
    order = {s.get("id"): i for i, s in enumerate(index.get("states", []))}
    table = {k: v for k, v in (index.get("scenes") or {}).items() if not k.startswith("_")}
    flags: set[str] = set()
    prev = -1
    prev_day = 0
    seen = set()
    for s in mains:
        sid = s["id"]
        flags |= {f for f in s.get("requires", {}).get("flags", [])}
        st = state_for(index, flags)
        seen.add(sid)
        want = table.get(sid)
        if want is None:
            err(f"{tag}scenes: нет сцены {sid} (каждая сцена основной истории — ровно одно состояние; сейчас выходит {st})")
        elif want != st:
            err(f"{tag}scenes.{sid}: записано {want}, а по флагам сцена начинается в {st}")
        i = order.get(st, -1)
        day = next((int(x.get("day", 0)) for x in index.get("states", []) if x.get("id") == st), 0)
        if i < prev:
            err(f"{tag}{sid}: время пошло назад ({st} после более позднего состояния)")
        if day < prev_day:
            err(f"{tag}{sid}: день {day} раньше прежнего {prev_day}")
        prev, prev_day = max(prev, i), max(prev_day, day)
        flags.add("done_" + sid)
        flags |= set(s.get("grants", {}).get("flags", []))
    for k in table:
        if k not in seen:
            err(f"{tag}scenes.{k}: такой сцены основной истории нет")


def check_grade_map(ctx: str, g: dict, states: set[str], phases: set[str]) -> None:
    for k, v in g.items():
        if k.startswith("_") or k == "inherit":
            continue
        if k not in states and k not in phases:
            err(f"{ctx}: ключ {k} — не состояние и не фаза")
        if v in ("painted", "none", None):
            continue
        if not isinstance(v, dict) or not COLOR.match(str(v.get("tint", ""))):
            err(f"{ctx}.{k}: ожидается {{\"tint\": \"#rrggbb\"}} или \"painted\"")


def main() -> int:
    quiet = "--quiet" in sys.argv
    if not (TIME / "_index.json").exists():
        print("validate_time: нет data/story/time/_index.json")
        return 1
    index = load(TIME / "_index.json")
    texts: dict = {}
    for tf in sorted((STORY / "text").glob("*.json")):
        texts.update(load(tf).get("texts", {}))
    mains = main_scenes()
    check_states(index, texts, mains)
    check_scenes(index, mains)
    states = {s["id"] for s in index.get("states", [])}
    phases = {s.get("phase") for s in index.get("states", [])}
    classes = {k for k in (index.get("grades") or {}) if not k.startswith("_")}
    for cls, g in (index.get("grades") or {}).items():
        if cls.startswith("_"):
            continue
        check_grade_map(f"grades.{cls}", g, states, phases)
        if g.get("inherit") and g["inherit"] not in classes:
            err(f"grades.{cls}.inherit: нет класса {g['inherit']}")
    rooms_dir = STORY / "rooms"
    flags_doc = set(load(STORY / "flags.json").get("flags", {}).keys())
    granted = set()
    for f in (STORY / "scenes").glob("*.json"):
        for s in load(f).get("scenes", []):
            granted |= set(s.get("grants", {}).get("flags", []))
    known = flags_doc | granted | tod_flags(index)
    room_only = {s["id"] for s in index.get("states", []) if s.get("room_only")}
    for l in index.get("locals", []):
        for r in l.get("rooms", []):
            if not (rooms_dir / f"{r}.json").exists():
                err(f"locals: комнаты {r} нет")
        if l.get("state") not in room_only:
            err(f"locals: state {l.get('state')!r} — должно быть состояние room_only")
    files = sorted(p for p in TIME.glob("*.json") if not p.name.startswith("_"))
    for p in files:
        d = load(p)
        rid = p.stem
        ctx = f"time/{p.name}"
        rf = rooms_dir / f"{rid}.json"
        if not rf.exists():
            err(f"{ctx}: комнаты {rid} нет в data/story/rooms")
            continue
        room = load(rf)
        if d.get("room", rid) != rid:
            err(f"{ctx}: room {d.get('room')!r} ≠ имени файла")
        if d.get("class") and d["class"] not in classes:
            err(f"{ctx}: класса {d['class']} нет в _index.grades")
        if d.get("fixed_state") and d["fixed_state"] not in states:
            err(f"{ctx}: fixed_state {d['fixed_state']} — нет такого состояния")
        check_grade_map(f"{ctx}.grade", d.get("grade", {}) or {}, states, phases)
        effects = {e.get("id") for e in room.get("effects", [])}
        for e in d.get("replaces_effects", []):
            if e not in effects:
                err(f"{ctx}: replaces_effects {e} — в rooms/{rid}.json такого эффекта нет")
        for w in d.get("windows", []):
            wc = f"{ctx}.windows.{w.get('id', '?')}"
            pts = w.get("points") or ([[w["rect"][0], w["rect"][1]], [w["rect"][0] + w["rect"][2], w["rect"][1] + w["rect"][3]]] if "rect" in w else [])
            if len(pts) < 2:
                err(f"{wc}: нужен rect [x, y, w, h] или points")
            for x, y in pts:
                if not (-1 <= x <= 1921 and -1 <= y <= 1081):
                    err(f"{wc}: точка ({x}, {y}) вне кадра 1920×1080")
            if w.get("color") and not COLOR.match(str(w["color"])):
                err(f"{wc}: color — «#rrggbb»")
            if not 0.0 < float(w.get("alpha", 0.5)) <= 1.0:
                err(f"{wc}: alpha 0..1")
            if w.get("blend", "add") not in ("add", "mul"):
                err(f"{wc}: blend — add (горящее окно) или mul (окно гаснет)")
            for k in ("if", "unless", "if_any"):
                for f in w.get(k, []) or []:
                    if f not in known and not f.startswith(AUTO):
                        err(f"{wc}.{k}: неизвестный флаг {f}")
    # Самопроверка: два состояния одного дня в обратном порядке должны дать ошибку.
    n0 = len(errors)
    broken = json.loads(json.dumps(index))
    st = [s for s in broken["states"] if s.get("day") == 2 and not s.get("room_only")]
    if len(st) >= 2:
        i, j = broken["states"].index(st[0]), broken["states"].index(st[-1])
        broken["states"][i], broken["states"][j] = broken["states"][j], broken["states"][i]
        check_states(broken, texts, mains, tag="[самопроверка] ")
        check_scenes(broken, mains, tag="[самопроверка] ")
    caught = len(errors) > n0
    del errors[n0:]
    if not caught:
        err("самопроверка: перестановка состояний второго дня не дала ошибки — проверка порядка не работает")
    for e in errors:
        print("ERROR " + e)
    print(f"validate_time: {'OK' if not errors else 'FAIL'} ({len(index.get('states', []))} состояний, {len(files)} комнат с файлом, "
          f"{len(mains)} сцен основной истории, {len(errors)} ошибок)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
