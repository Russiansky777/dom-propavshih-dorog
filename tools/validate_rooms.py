#!/usr/bin/env python3
"""Проверка комнат data/story/rooms/*.json против сценария (уровень 1, тест (a) M1).

Проверяет:
  1. у каждой локации сцен E0–E1 и Q04 есть файл комнаты; id совпадает с именем файла;
  2. выходы: каждый переход locations.json, касающийся построенной комнаты, описан в ней
     (в обе стороны); цель выхода — известная локация; цели вне in_scope — заглушки (отчёт);
     спавн, на который ссылается выход, существует в целевой комнате;
  3. хотспоты: все флаги в sets/visible_if/hidden_if/states/requires/complete_when существуют
     (flags.json, автофлаги, выдачи сцен, выборы, локальные флаги комнат); все предметы существуют;
     gives — только предметы, чей source_scene совпадает со сценой шага и чья сцена идёт в этой комнате;
     sets со сценой — только флаги из grants сцены или локальные флаги комнаты;
  4. все текстовые ключи @… есть в data/story/text/*.json (кроме @char.<id> из characters.json);
  5. геометрия: полигон ≥ 3 точек; точки stand хотспотов/выходов и спавны лежат внутри полигона.

Код 0 — ошибок нет. Запуск: python3 tools/validate_rooms.py [--quiet]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
ROOMS = STORY / "rooms"
TEXT = STORY / "text"

errors: list[str] = []
warnings: list[str] = []
notes: list[str] = []


def err(m: str) -> None:
    errors.append(m)


def warn(m: str) -> None:
    warnings.append(m)


def load(path: Path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# ---------- данные сценария ----------
index = load(ROOMS / "_index.json")
in_scope: list[str] = index["in_scope"]
sides = index["sides"]
auto_prefixes = tuple(index.get("auto_flag_prefixes", ["done_", "has_", "started_", "q0", "q1"]))

locations = load(STORY / "locations.json")
items = {i["id"]: i for i in load(STORY / "items.json")["items"]}
flags_doc = load(STORY / "flags.json")["flags"]
characters = {c["id"] for c in load(STORY / "characters.json")["characters"]}
quests = load(STORY / "quests.json")["quests"]

scenes: dict[str, dict] = {}
for ep_file in sorted((STORY / "scenes").glob("E*.json")):
    for sc in load(ep_file)["scenes"]:
        scenes[sc["id"]] = sc
for q in quests:
    q = dict(q)
    q.setdefault("grants", {"flags": [], "items": []})
    q["grants"] = {"flags": list(q["grants"].get("flags", [])) + [o["sets"] for o in q["choice"]["options"]],
                   "items": list(q["grants"].get("items", []))}
    scenes[q["id"]] = q

loc_ids = {l["id"] for l in locations["locations"]}
edges: dict[str, dict[str, list[str]]] = {l: {} for l in loc_ids}
for e in locations["edges"]:
    edges[e["from"]][e["to"]] = list(e["requires"])
    edges[e["to"]][e["from"]] = list(e["requires"])

texts: dict[str, dict] = {}
for tf in sorted(TEXT.glob("*.json")):
    texts.update(load(tf)["texts"])

known_flags: set[str] = set(flags_doc.keys())
for sc in scenes.values():
    known_flags |= set(sc.get("grants", {}).get("flags", []))
    for it in sc.get("grants", {}).get("items", []):
        known_flags.add("has_" + it)
for e in locations["edges"]:
    known_flags |= set(e["requires"])

# ---------- комнаты ----------
rooms: dict[str, dict] = {}
for rf in sorted(ROOMS.glob("*.json")):
    if rf.name.startswith("_"):
        continue
    try:
        data = load(rf)
    except json.JSONDecodeError as ex:
        err(f"{rf.name}: не JSON: {ex}")
        continue
    if data.get("id") != rf.stem:
        err(f"{rf.name}: id '{data.get('id')}' не совпадает с именем файла")
    rooms[rf.stem] = data
    for fl, desc in data.get("flags", {}).items():
        if not isinstance(desc, str) or not desc:
            err(f"{rf.stem}: локальный флаг {fl} без описания")
        known_flags.add(fl)
    for h in data.get("hotspots", []):
        ch = h.get("choice")
        if ch:
            for o in ch.get("options", []):
                if "sets" in o:
                    known_flags.add(o["sets"])

for rid in in_scope:
    if rid not in rooms:
        err(f"комната {rid} в in_scope, но файла нет")
    if rid not in loc_ids:
        err(f"комната {rid} не является локацией locations.json")

# 1. локации сцен в объёме вехи
scope_scenes = [s for s in scenes.values() if s["id"].startswith(("M0", "V0")) and int(s["id"][1:]) <= 8] + [scenes["Q04"]]
scope_scenes = [s for s in scope_scenes if s["id"] in ("M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "V01", "V02", "V03", "Q04")]
for s in scope_scenes:
    for loc in s["locations"]:
        if loc not in rooms:
            err(f"сцена {s['id']}: локация {loc} без файла комнаты")


def flag_known(fl: str) -> bool:
    return fl in known_flags or fl.startswith(auto_prefixes)


def check_flags(ctx: str, flags) -> None:
    for fl in flags or []:
        if not flag_known(fl):
            err(f"{ctx}: неизвестный флаг {fl}")


def check_items(ctx: str, its) -> None:
    for it in its or []:
        if it not in items:
            err(f"{ctx}: неизвестный предмет {it}")


def check_text(ctx: str, value) -> None:
    if not isinstance(value, str) or not value.startswith("@"):
        return
    key = value[1:]
    if key.startswith("char."):
        if key[5:] not in characters:
            err(f"{ctx}: неизвестный персонаж {key}")
        return
    if key not in texts:
        err(f"{ctx}: нет текста для ключа {value}")


def walk_texts(ctx: str, obj) -> None:
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in ("label", "text", "look", "closed_text", "fail_text", "before_text", "after_text", "prompt",
                     "title", "intro", "check_label", "close_label", "error_text", "success_text", "complete_text",
                     "drawing_label", "error_hint"):
                check_text(f"{ctx}.{k}", v)
            walk_texts(f"{ctx}.{k}", v)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            walk_texts(f"{ctx}[{i}]", v)


def point_in_poly(pt, poly) -> bool:
    x, y = pt
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xin = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            if x < xin:
                inside = not inside
    return inside


def exit_geometry(room: dict, ex: dict):
    """Повторяет RoomBuilder.exit_geometry: возвращает (rect, stand)."""
    if "rect" in ex and "stand" in ex:
        return ex["rect"], ex["stand"]
    side = ex.get("side")
    horizon = room.get("background", {}).get("horizon", 640)
    if side in ("left", "right"):
        return sides[side]["rect"], sides[side]["stand"]
    if side == "back":
        x = ex["x"]
        s = sides["back"]
        return [x - s["half_w"], s["top"], 2 * s["half_w"], horizon - s["top"]], [x, horizon + s["stand_below_horizon"]]
    if side == "bottom":
        x = ex["x"]
        s = sides["bottom"]
        return [x - s["half_w"], s["top"], 2 * s["half_w"], s["h"]], [x, s["stand_y"]]
    return None, None


def walkable_of(room: dict):
    if "walkable" in room:
        return room["walkable"]
    kind = room.get("background", {}).get("kind", "interior")
    return index["defaults"]["walkable_exterior" if kind == "exterior" else "walkable_interior"]


stubs: list[str] = []
for rid, room in rooms.items():
    ctx = rid
    poly = walkable_of(room)
    if len(poly) < 3:
        err(f"{ctx}: полигон Walkable короче 3 точек")
    walk_texts(ctx, room)

    # спавны
    spawns = room.get("spawns", {})
    if "default" not in spawns:
        err(f"{ctx}: нет спавна default")
    for sid, pos in spawns.items():
        if not point_in_poly(pos, poly):
            err(f"{ctx}: спавн {sid} {pos} вне полигона")

    # 2. выходы против рёбер
    exits = room.get("exits", [])
    seen_targets = set()
    for ex in exits:
        to = ex.get("to")
        if to not in loc_ids:
            err(f"{ctx}: выход в неизвестную локацию {to}")
            continue
        if to in seen_targets:
            err(f"{ctx}: выход в {to} описан дважды")
        seen_targets.add(to)
        if to not in edges[rid]:
            err(f"{ctx}: выход в {to} не соответствует ни одному переходу locations.json")
        rect, stand = exit_geometry(room, ex)
        if rect is None:
            err(f"{ctx}: выход в {to} без side/rect")
        elif not point_in_poly(stand, poly):
            err(f"{ctx}: stand выхода в {to} {stand} вне полигона")
        if to in rooms:
            sp = ex.get("spawn", "default")
            if sp not in rooms[to].get("spawns", {}):
                err(f"{ctx}: выход в {to} ссылается на спавн {sp}, которого нет в {to}")
        elif to in in_scope:
            err(f"{ctx}: выход в {to} — комната в in_scope без файла")
        else:
            stubs.append(f"{rid}→{to}")
        oc = ex.get("on_closed")
        if oc:
            check_flags(f"{ctx}.exit[{to}].on_closed", oc.get("sets"))
            if oc.get("spawn") and oc["spawn"] not in spawns:
                err(f"{ctx}: on_closed выхода в {to} ссылается на спавн {oc['spawn']}")
            if oc.get("scene") and oc["scene"] not in scenes:
                err(f"{ctx}: on_closed выхода в {to} ссылается на сцену {oc['scene']}")
    for to in edges[rid]:
        if to not in seen_targets:
            err(f"{ctx}: переход {rid}–{to} из locations.json не имеет выхода в комнате")

    # 3. хотспоты
    ids = set()
    for h in room.get("hotspots", []):
        hid = h.get("id")
        hctx = f"{ctx}.{hid}"
        if hid in ids:
            err(f"{hctx}: повтор id хотспота")
        ids.add(hid)
        if "rect" not in h or "stand" not in h:
            err(f"{hctx}: нет rect/stand")
        elif not point_in_poly(h["stand"], poly):
            err(f"{hctx}: stand {h['stand']} вне полигона")
        check_flags(hctx + ".visible_if", h.get("visible_if"))
        check_flags(hctx + ".hidden_if", h.get("hidden_if"))
        for st in h.get("states", []):
            check_flags(hctx + ".states", st.get("if"))

        def check_action(actx: str, act: dict, scene_id: str | None) -> None:
            req = act.get("requires", {})
            check_flags(actx + ".requires", req.get("flags"))
            check_items(actx + ".requires", req.get("items"))
            check_flags(actx + ".sets", act.get("sets"))
            check_items(actx + ".gives", act.get("gives"))
            check_items(actx + ".consumes", act.get("consumes") if isinstance(act.get("consumes"), list) else None)
            if act.get("once_flag"):
                check_flags(actx + ".once_flag", [act["once_flag"]])
            if scene_id:
                if scene_id not in scenes:
                    err(f"{actx}: неизвестная сцена {scene_id}")
                    return
                sc = scenes[scene_id]
                if rid not in sc["locations"]:
                    err(f"{actx}: сцена {scene_id} не идёт в {rid} (locations={sc['locations']})")
                gr = sc.get("grants", {})
                for fl in act.get("sets", []) or []:
                    if fl not in gr.get("flags", []) and fl not in room.get("flags", {}):
                        err(f"{actx}: флаг {fl} не входит в grants сцены {scene_id} и не локальный")
                for it in act.get("gives", []) or []:
                    if it not in gr.get("items", []):
                        err(f"{actx}: предмет {it} не входит в grants сцены {scene_id}")
                    elif items[it]["source_scene"] != scene_id:
                        err(f"{actx}: предмет {it} по items.json выдаётся в {items[it]['source_scene']}, а не в {scene_id}")
                    elif not items[it].get("inventory", False):
                        err(f"{actx}: предмет {it} не инвентарный, его нельзя взять хотспотом")
            else:
                for it in act.get("gives", []) or []:
                    err(f"{actx}: выдача предмета {it} без указания сцены")

        if "use" in h:
            check_action(hctx + ".use", h["use"], h["use"].get("scene"))
        for it, act in (h.get("item_use") or {}).items():
            check_items(hctx + ".item_use", [it])
            check_action(f"{hctx}.item_use[{it}]", act, act.get("scene"))
        if "talk" in h:
            scn = h["talk"].get("scene")
            if scn and scn not in scenes:
                err(f"{hctx}.talk: неизвестная сцена {scn}")
            elif scn and rid not in scenes[scn]["locations"]:
                err(f"{hctx}.talk: сцена {scn} не идёт в {rid}")
        if "choice" in h:
            ch = h["choice"]
            check_flags(hctx + ".choice.requires", ch.get("requires", {}).get("flags"))
            for o in ch.get("options", []):
                if "sets" not in o or "id" not in o:
                    err(f"{hctx}.choice: вариант без id/sets")
            scn = ch.get("scene")
            if scn and scn not in scenes:
                err(f"{hctx}.choice: неизвестная сцена {scn}")
        if "puzzle" in h:
            pz = h["puzzle"]
            check_flags(hctx + ".puzzle.requires", pz.get("requires", {}).get("flags"))
            check_items(hctx + ".puzzle.requires", pz.get("requires", {}).get("items"))
            scn = pz.get("success", {}).get("scene")
            if scn not in scenes:
                err(f"{hctx}.puzzle: неизвестная сцена успеха {scn}")
            if pz.get("type") == "match_marks":
                correct = [s for s in pz.get("slots", []) if s.get("correct")]
                if len(correct) != len(pz.get("pieces", [])):
                    err(f"{hctx}.puzzle: число правильных гнёзд ({len(correct)}) != число деталей ({len(pz.get('pieces', []))})")
                mk = pz.get("marks", {})
                if not (0 <= mk.get("correct", -1) < len(mk.get("positions", []))):
                    err(f"{hctx}.puzzle: marks.correct вне диапазона")

    # сцены комнаты
    for sid, spec in room.get("scenes", {}).items():
        sctx = f"{ctx}.scenes.{sid}"
        if sid not in scenes:
            err(f"{sctx}: неизвестная сцена")
            continue
        if rid not in scenes[sid]["locations"]:
            err(f"{sctx}: сцена не идёт в {rid}")
        cw = spec.get("complete_when")
        if cw is not None:
            if isinstance(cw, dict):
                cw = [cw]
            for cond in cw:
                check_flags(sctx + ".complete_when", cond.get("all"))
                check_flags(sctx + ".complete_when", cond.get("any"))
                check_flags(sctx + ".complete_when", cond.get("flags"))
        trig = spec.get("trigger", "")
        if trig.startswith("talk:") and trig[5:] not in ids:
            err(f"{sctx}: trigger ссылается на хотспот {trig[5:]}")
        if trig.startswith("puzzle:") and trig[7:] not in ids:
            err(f"{sctx}: trigger ссылается на хотспот {trig[7:]}")

# сцены в объёме: у каждой есть способ запуска (trigger/complete_when в какой-то из её комнат)
for s in scope_scenes:
    ways = []
    for loc in s["locations"]:
        room = rooms.get(loc, {})
        spec = room.get("scenes", {}).get(s["id"])
        if spec:
            ways.append(f"{loc}:{spec.get('trigger', 'complete_when' if 'complete_when' in spec else 'enter')}")
    if not ways:
        warn(f"сцена {s['id']} не упомянута ни в одной комнате — запустится при входе в {s['locations']}, как только выполнены requires")
    else:
        notes.append(f"{s['id']}: {', '.join(ways)}")

quiet = "--quiet" in sys.argv
if stubs and not quiet:
    notes.append("выходы-заглушки (вне in_scope): " + ", ".join(stubs))
if not quiet:
    for n in notes:
        print("  " + n)
    for w in warnings:
        print("WARN: " + w)
for e in errors:
    print("ERROR: " + e)
print(f"rooms: {len(rooms)} файлов, {len(errors)} ошибок, {len(warnings)} предупреждений, {len(texts)} текстов")
sys.exit(1 if errors else 0)
