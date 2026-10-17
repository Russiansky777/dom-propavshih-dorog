#!/usr/bin/env python3
"""Проверка света комнат data/story/lights/<LOC>.json (RoomLighting, game/scripts/lighting).

Проверяет:
  1. файл — JSON-объект, `room` совпадает с именем файла, комната есть в data/story/rooms и в in_scope;
  2. sources[]: id уникальны; type ∈ ambient | point | mask | shaft | fire | glow; обязательные поля
     типа (ambient: subtract [r,g,b] 0..1; point: pos, radius > 0; mask/shaft: polygons ≥ 3 точек,
     feather > 0; fire/glow: rect [x,y,w,h], w,h > 0); координаты в кадре 1920x1080 (± 200 px);
  3. флаги if / unless / energy_if[].if / energy_if[].unless известны (flags.json, выдачи сцен,
     требования переходов, локальные флаги комнат, выборы, has_<предмет>, автопрефиксы) —
     та же база, что у validate_rooms.py;
  4. suppress_effects — id, которые есть в effects[] комнаты;
  5. casts_actor_shadow → shadow.floor [x, y] в кадре, alpha/alpha_far в 0..1, near_px < far_px;
  6. цвета: "#rrggbb" или [r, g, b(, a)] в 0..1; fade_s в 0..5; flicker.amount в 0..1;
  7. params у fire/glow — существующие uniform шейдера (game/shaders/fire_stove|light_glow.gdshader);
     у shaft — streak_amount 0..1;
  8. тон актёров: actor_tint (у комнаты и у источников) — [r, g, b] в 0..1.5; actor_warm — {color
     [r, g, b] в −0.3..1, near_px < far_px, floor?}; actor_max_gain 0.5..2, actor_max_cool 0..0.5.
Код 0 — ошибок нет. Запуск: python3 tools/validate_lights.py [--quiet]
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
LIGHTS = STORY / "lights"
ROOMS = STORY / "rooms"
SHADERS = ROOT / "game" / "shaders"

TYPES = {"ambient", "point", "mask", "shaft", "fire", "glow"}
SHADER_OF = {"fire": "fire_stove.gdshader", "glow": "light_glow.gdshader"}
FRAME = (-200.0, -200.0, 2120.0, 1280.0)

errors: list[str] = []
notes: list[str] = []


def err(m: str) -> None:
    errors.append(m)


def load(path: Path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def known_flag_set() -> tuple[set[str], tuple[str, ...]]:
    index = load(ROOMS / "_index.json")
    auto = tuple(index.get("auto_flag_prefixes", ["done_", "has_", "started_", "q0", "q1"]))
    known: set[str] = set(load(STORY / "flags.json")["flags"].keys())
    for ep in sorted((STORY / "scenes").glob("E*.json")):
        for sc in load(ep)["scenes"]:
            g = sc.get("grants", {})
            known |= set(g.get("flags", []))
            known |= {"has_" + it for it in g.get("items", [])}
    for q in load(STORY / "quests.json")["quests"]:
        known |= set(q.get("grants", {}).get("flags", []))
        for o in q.get("choice", {}).get("options", []):
            if "sets" in o:
                known.add(o["sets"])
    for e in load(STORY / "locations.json")["edges"]:
        known |= set(e.get("requires", []))
    for rf in ROOMS.glob("*.json"):
        if rf.name.startswith("_"):
            continue
        room = load(rf)
        known |= set(room.get("flags", {}).keys())
        for h in room.get("hotspots", []):
            for o in h.get("choice", {}).get("options", []):
                if "sets" in o:
                    known.add(o["sets"])
    return known, auto


def is_num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def check_point(ctx: str, p) -> bool:
    if not (isinstance(p, list) and len(p) == 2 and all(is_num(v) for v in p)):
        err(f"{ctx}: ожидается точка [x, y], получено {p!r}")
        return False
    if not (FRAME[0] <= p[0] <= FRAME[2] and FRAME[1] <= p[1] <= FRAME[3]):
        err(f"{ctx}: точка {p} вне кадра 1920x1080")
        return False
    return True


def check_color(ctx: str, c) -> None:
    if isinstance(c, str):
        if not re.fullmatch(r"#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", c):
            err(f"{ctx}: цвет {c!r} не #rrggbb")
    elif isinstance(c, list):
        if len(c) not in (3, 4) or not all(is_num(v) and 0.0 <= v <= 1.0 for v in c):
            err(f"{ctx}: цвет {c!r} — ожидается [r, g, b(, a)] в 0..1")
    else:
        err(f"{ctx}: цвет {c!r} неизвестного вида")


def shader_uniforms(name: str) -> set[str]:
    path = SHADERS / name
    if not path.exists():
        err(f"шейдер {path} не найден")
        return set()
    return set(re.findall(r"^\s*uniform\s+\w+\s+(\w+)", path.read_text(encoding="utf-8"), re.M))


def main() -> int:
    quiet = "--quiet" in sys.argv
    if not LIGHTS.is_dir():
        print("[lights] нет data/story/lights — нечего проверять")
        return 0
    index = load(ROOMS / "_index.json")
    in_scope = set(index.get("in_scope", []))
    known, auto = known_flag_set()

    def check_flags(ctx: str, flags) -> None:
        if flags is None:
            return
        if not isinstance(flags, list):
            err(f"{ctx}: ожидается список флагов")
            return
        for fl in flags:
            if not isinstance(fl, str) or not (fl in known or fl.startswith(auto)):
                err(f"{ctx}: неизвестный флаг {fl!r}")

    files = sorted(LIGHTS.glob("*.json"))
    total_sources = 0
    for lf in files:
        ctx0 = f"lights/{lf.name}"
        try:
            data = load(lf)
        except json.JSONDecodeError as ex:
            err(f"{ctx0}: не JSON: {ex}")
            continue
        if not isinstance(data, dict):
            err(f"{ctx0}: ожидается объект")
            continue
        rid = lf.stem
        if data.get("room") != rid:
            err(f"{ctx0}: room {data.get('room')!r} не совпадает с именем файла")
        room_path = ROOMS / f"{rid}.json"
        if not room_path.exists():
            err(f"{ctx0}: нет комнаты data/story/rooms/{rid}.json")
            continue
        if rid not in in_scope:
            err(f"{ctx0}: комната {rid} не в in_scope")
        room = load(room_path)
        effect_ids = {e.get("id") for e in room.get("effects", [])}
        for eid in data.get("suppress_effects", []):
            if eid not in effect_ids:
                err(f"{ctx0}: suppress_effects {eid!r} — в rooms/{rid}.json нет такого effects[].id")
        for key_ctx, holder in [(ctx0, data)] + [(f"{ctx0}:{s.get('id', '?')}", s) for s in data.get("sources", []) if isinstance(s, dict)]:
            at = holder.get("actor_tint")
            if at is not None and not (isinstance(at, list) and len(at) == 3 and all(is_num(v) and 0.0 <= v <= 1.5 for v in at)):
                err(f"{key_ctx}: actor_tint — [r, g, b] в 0..1.5")
            aw = holder.get("actor_warm")
            if aw is not None:
                if not isinstance(aw, dict) or "color" not in aw:
                    err(f"{key_ctx}: actor_warm — объект {{color, near_px, far_px}}")
                else:
                    wc = aw["color"]
                    if not (isinstance(wc, list) and len(wc) == 3 and all(is_num(v) and -0.3 <= v <= 1.0 for v in wc)):
                        err(f"{key_ctx}: actor_warm.color — [r, g, b] в −0.3..1 (отрицательное — холоднее)")
                    if "floor" in aw:
                        check_point(key_ctx + ".actor_warm.floor", aw["floor"])
                    if not (aw.get("near_px", 150) < aw.get("far_px", 900)):
                        err(f"{key_ctx}: actor_warm near_px < far_px")
        for k, lo, hi in (("actor_max_gain", 0.5, 2.0), ("actor_max_cool", 0.0, 0.5)):
            if k in data and not (is_num(data[k]) and lo <= data[k] <= hi):
                err(f"{ctx0}: {k} вне {lo}..{hi}")
        fs = data.get("floor_foreshortening", 0.42)
        if not (is_num(fs) and 0.1 <= fs <= 1.0):
            err(f"{ctx0}: floor_foreshortening {fs!r} вне 0.1..1")
        sources = data.get("sources", [])
        if not isinstance(sources, list) or not sources:
            err(f"{ctx0}: sources пуст или не список")
            continue
        seen: set[str] = set()
        for i, s in enumerate(sources):
            sid = s.get("id", f"#{i}")
            ctx = f"{ctx0}:{sid}"
            total_sources += 1
            if sid in seen:
                err(f"{ctx}: повтор id")
            seen.add(sid)
            t = s.get("type")
            if t not in TYPES:
                err(f"{ctx}: type {t!r} не из {sorted(TYPES)}")
                continue
            check_flags(ctx + ".if", s.get("if"))
            check_flags(ctx + ".unless", s.get("unless"))
            for j, e in enumerate(s.get("energy_if", [])):
                check_flags(f"{ctx}.energy_if[{j}].if", e.get("if"))
                check_flags(f"{ctx}.energy_if[{j}].unless", e.get("unless"))
                if not is_num(e.get("energy")):
                    err(f"{ctx}.energy_if[{j}]: нет числа energy")
            fade = s.get("fade_s", 0.8)
            if not (is_num(fade) and 0.0 <= fade <= 5.0):
                err(f"{ctx}: fade_s {fade!r} вне 0..5")
            if "energy" in s and not (is_num(s["energy"]) and 0.0 <= s["energy"] <= 4.0):
                err(f"{ctx}: energy {s['energy']!r} вне 0..4")
            if "color" in s:
                check_color(ctx + ".color", s["color"])
            fl = s.get("flicker")
            if fl is not None:
                if not isinstance(fl, dict):
                    err(f"{ctx}: flicker — объект {{group, amount, speed}}")
                else:
                    if not (is_num(fl.get("amount", 0)) and 0.0 <= fl.get("amount", 0) <= 1.0):
                        err(f"{ctx}: flicker.amount вне 0..1")
                    if not (is_num(fl.get("speed", 1)) and 0.0 < fl.get("speed", 1) <= 10.0):
                        err(f"{ctx}: flicker.speed вне (0..10]")
            if t == "ambient":
                sub = s.get("subtract")
                if not (isinstance(sub, list) and len(sub) == 3 and all(is_num(v) and 0.0 <= v <= 1.0 for v in sub)):
                    err(f"{ctx}: subtract — [r, g, b] в 0..1")
            elif t == "point":
                check_point(ctx + ".pos", s.get("pos"))
                if not (is_num(s.get("radius")) and s["radius"] > 0):
                    err(f"{ctx}: radius > 0 обязателен")
            elif t in ("mask", "shaft"):
                polys = s.get("polygons")
                if not (isinstance(polys, list) and polys):
                    err(f"{ctx}: polygons — список многоугольников")
                else:
                    for k, poly in enumerate(polys):
                        if not (isinstance(poly, list) and len(poly) >= 3):
                            err(f"{ctx}.polygons[{k}]: меньше 3 точек")
                            continue
                        for p in poly:
                            check_point(f"{ctx}.polygons[{k}]", p)
                if not (is_num(s.get("feather", 40)) and s.get("feather", 40) > 0):
                    err(f"{ctx}: feather > 0")
                g = s.get("gradient")
                if g is not None:
                    check_point(ctx + ".gradient.from", g.get("from"))
                    check_point(ctx + ".gradient.to", g.get("to"))
                if t == "shaft" and "streak_amount" in s and not (is_num(s["streak_amount"]) and 0 <= s["streak_amount"] <= 1):
                    err(f"{ctx}: streak_amount вне 0..1")
                if "mode" in s and s["mode"] not in ("add", "sub"):
                    err(f"{ctx}: mode {s['mode']!r} — add | sub")
            elif t in ("fire", "glow"):
                r = s.get("rect")
                if not (isinstance(r, list) and len(r) == 4 and all(is_num(v) for v in r) and r[2] > 0 and r[3] > 0):
                    err(f"{ctx}: rect [x, y, w, h] с w, h > 0")
                else:
                    check_point(ctx + ".rect", [r[0], r[1]])
                    check_point(ctx + ".rect(end)", [r[0] + r[2], r[1] + r[3]])
                uni = shader_uniforms(SHADER_OF[t])
                for k in s.get("params", {}):
                    if uni and k not in uni:
                        err(f"{ctx}.params: {k!r} — нет такого uniform в {SHADER_OF[t]}")
            if s.get("casts_actor_shadow"):
                sh = s.get("shadow", {})
                if not isinstance(sh, dict):
                    err(f"{ctx}: shadow — объект")
                    continue
                check_point(ctx + ".shadow.floor", sh.get("floor"))
                for k in ("alpha", "alpha_far", "head_fade"):
                    if k in sh and not (is_num(sh[k]) and 0.0 <= sh[k] <= 1.0):
                        err(f"{ctx}.shadow.{k} вне 0..1")
                near, far = sh.get("near_px", 90), sh.get("far_px", 1200)
                if not (is_num(near) and is_num(far) and 0 <= near < far):
                    err(f"{ctx}.shadow: near_px < far_px")
                for k in ("len", "len_far"):
                    if k in sh and not (is_num(sh[k]) and 0.0 < sh[k] <= 3.0):
                        err(f"{ctx}.shadow.{k} вне (0..3]")
        notes.append(f"{rid}: {len(sources)} источников, тени от: {', '.join(s.get('id', '?') for s in sources if s.get('casts_actor_shadow')) or '—'}")

    if not quiet:
        for n in notes:
            print("  " + n)
    for e in errors:
        print("ERROR " + e)
    print(f"[lights] {'OK' if not errors else 'FAIL'}: {len(files)} файлов, {total_sources} источников, {len(errors)} ошибок")
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
