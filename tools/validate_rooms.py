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
  5. геометрия: полигон ≥ 3 точек; точки stand хотспотов/выходов и спавны лежат внутри полигона;
     вырезы (walkable_holes) лежат в кадре и пересекают пол;
  6. геометрия по картинке (дефект «Агата проходит сквозь стойку/стол/воду»): у каждой комнаты
     in_scope есть no_walk_samples (≥ 2 точки заведомо внутри препятствий/воды — вне пола или в
     вырезе) и walk_samples (≥ 3 точки свободного пола — на полу и не в вырезе); nearest_checks
     ({from, in:[x,y,w,h]}) — from вне пола. Те же точки проверяет навигацией Godot
     game/tests/test_room_geometry.gd;
  7. масштаб (Директор: «стул слишком большой, сцена приближена»): фон вписан в 1920x1080 целиком —
     масштаб 1920/ширина ± 0.001, по высоте без обрезки и полос (± 2 px); каждый слой и состояние
     рисуются тем же масштабом (RoomBuilder: art_scale × scale) — scale ≠ 1 только с scale_reason.
     Фактические масштабы узлов сверяет test_room_geometry.gd;
  8. рост Агаты (Директор: «соразмерна дверным проёмам, стойке, партам»): для каждого ориентира
     height_refs комнаты рост Агаты agata_ref.figure_px × scale(y) отличается от
     agata_ref.height_m × px / m не больше чем на agata_ref.tolerance; scale(y) — прямая глубины
     (Room.depth_scale без зажима: ориентиры у стены стоят дальше кромки пола). Таблица — без --quiet.

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
GAME_DIR = ROOT / "game"
FRAME_W, FRAME_H = 1920, 1080
SCALE_TOL = 0.001


def png_size(res: str):
    """(w, h) из заголовка PNG по пути res://… (без Pillow: CI ставит только Godot)."""
    path = GAME_DIR / res[len("res://"):]
    try:
        with open(path, "rb") as f:
            head = f.read(24)
    except OSError:
        return None
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    import struct
    return struct.unpack(">II", head[16:24])


def art_scale(room: dict):
    """Повторяет RoomBuilder._build_background: масштаб фона = 1920 / ширина картинки."""
    img = room.get("background", {}).get("image")
    size = png_size(img) if img else None
    return (FRAME_W / size[0], size) if size and size[0] > 0 else (None, size)


def check_res_path(ctx: str, res: str) -> None:
    """res://… должен существовать в game/ (иначе экспорт останется без картинки)."""
    if not res.startswith("res://"):
        err(f"{ctx}: путь {res} должен начинаться с res://")
        return
    if not (GAME_DIR / res[len("res://"):]).exists():
        err(f"{ctx}: файла {res} нет в game/")


for rid, room in rooms.items():
    ctx = rid
    poly = walkable_of(room)
    if len(poly) < 3:
        err(f"{ctx}: полигон Walkable короче 3 точек")
    walk_texts(ctx, room)
    if "image" in room.get("background", {}):
        check_res_path(f"{ctx}.background.image", room["background"]["image"])
    for p in room.get("props", []):
        if "image" in p:
            check_res_path(f"{ctx}.props.{p.get('id')}.image", p["image"])
        if p.get("occluder") and "z" in p and not (0 <= int(p["z"]) <= 4096):
            err(f"{ctx}.props.{p.get('id')}: z вне 0..4096")
    # 7. масштаб фона и слоёв
    bg_scale, bg_size = art_scale(room)
    if "image" in room.get("background", {}):
        if bg_scale is None:
            err(f"{ctx}.background.image: не читается как PNG")
        else:
            if abs(bg_scale - FRAME_W / bg_size[0]) > SCALE_TOL:
                err(f"{ctx}: масштаб фона {bg_scale:.5f} ≠ 1920/{bg_size[0]}")
            if abs(bg_size[1] * bg_scale - FRAME_H) > 2.0:
                err(f"{ctx}: фон {bg_size[0]}x{bg_size[1]} при масштабе 1920/ширина даёт высоту "
                    f"{bg_size[1] * bg_scale:.0f} px — кадр 1920x1080 будет обрезан или с полосами (нужен 16:9)")
    for l in room.get("layers", []):
        lctx = f"{ctx}.layers.{l.get('id', '?')}"
        sc = float(l.get("scale", 1.0))
        if abs(sc - 1.0) > SCALE_TOL and not str(l.get("scale_reason", "")).strip():
            err(f"{lctx}: scale {sc} без scale_reason — слои и состояния рисуются масштабом фона "
                f"({bg_scale:.4f}), отдельный масштаб только с объяснением")
        if "scale_reason" in l and abs(sc - 1.0) <= SCALE_TOL:
            warn(f"{lctx}: scale_reason при scale 1 — лишнее поле")
        if sc <= 0:
            err(f"{lctx}: scale {sc} ≤ 0")
        if "image" not in l:
            err(f"{lctx}: нет image")
        else:
            check_res_path(lctx + ".image", l["image"])
            lsize = png_size(l["image"])
            if (lsize and bg_size and "offset" not in l
                    and (abs(lsize[0] - bg_size[0]) > 2 or abs(lsize[1] - bg_size[1]) > 2)):
                warn(f"{lctx}: холст слоя {lsize[0]}x{lsize[1]} ≠ фон {bg_size[0]}x{bg_size[1]} и нет offset — "
                     f"при общем масштабе слой сдвинется, подгоните offset")
        check_flags(lctx + ".if", l.get("if"))
        check_flags(lctx + ".unless", l.get("unless"))
        if l.get("occluder") and "z" not in l:
            warn(f"{lctx}: окклюдер без явного z (будет 1080)")
    # 9. стоянка у NPC не закрывает его (дефект ui_10: в разговоре Агата встала прямо перед Тамарой).
    # Рамки фигур: Агата — figure_half_width_px × масштаб глубины в ширину, figure_px × масштаб в высоту,
    # ноги на стоянке. NPC (game/data/actors/<id>.json): обычный — ноги в нижней середине rect хотспота,
    # тот же размер × npc.scale_factor; кукла (type puppet, place.<LOC>: feet на экране, depth_y — пол
    # под ним) — высота height_rel_agata × figure_px × масштаб глубины, ширина ≈ высоте. Если Агата
    # ближе к зрителю (её y больше пола под NPC) и закрывает больше npc_overlap_max площади его рамки — ошибка.
    aref9 = index.get("agata_ref", {})
    kind9 = room.get("background", {}).get("kind", "interior")
    dep9 = room.get("depth", index["defaults"].get("depth_exterior" if kind9 == "exterior" else "depth", {}))

    def depth_scale(y: float) -> float:
        """Повторяет Room.depth_scale (с зажимом: так рисуется фигура)."""
        span = dep9["bottom_y"] - dep9["top_y"]
        t = 1.0 if span == 0 else min(1.0, max(0.0, (y - dep9["top_y"]) / span))
        return dep9["scale_top"] + (dep9["scale_bottom"] - dep9["scale_top"]) * t

    for h in room.get("hotspots", []):
        if h.get("kind") != "npc" or "rect" not in h or "stand" not in h or not aref9.get("figure_half_width_px"):
            continue
        r = h["rect"]
        sx, sy = h["stand"]
        hw, fig = aref9["figure_half_width_px"], aref9["figure_px"]
        actor_path = GAME_DIR / "data" / "actors" / f"{h.get('id')}.json"
        actor = load(actor_path) if actor_path.exists() else None
        if actor is None and "image" not in h:
            continue  # фигуры нет — закрывать нечего
        place = (actor or {}).get("place", {}).get(rid) if (actor or {}).get("type") == "puppet" else None
        if place:
            fx, fy = place["feet"]
            floor_y = place.get("depth_y", fy)
            if not (r[0] <= fx <= r[0] + r[2] and r[1] <= fy <= r[1] + r[3] + 8):
                err(f"{ctx}.{h.get('id')}: rect {r} не на фигуре куклы — её ноги {place['feet']} "
                    f"(game/data/actors/{h.get('id')}.json place.{rid}) вне прямоугольника клика")
            n_h = float(actor.get("height_rel_agata", 1.0)) * fig * depth_scale(floor_y)
            n_hw = n_h / 2
        else:
            fx, fy = r[0] + r[2] / 2, r[1] + r[3]
            floor_y = fy
            factor = float((actor or {}).get("npc", {}).get("scale_factor", 1.0))
            n_h = fig * depth_scale(fy) * factor
            n_hw = hw * depth_scale(fy) * factor
        a_s = depth_scale(sy)
        a_hw, a_h = hw * a_s, fig * a_s
        ox = min(sx + a_hw, fx + n_hw) - max(sx - a_hw, fx - n_hw)
        oy = min(sy, fy) - max(sy - a_h, fy - n_h)
        covered = max(0.0, ox) / (2 * n_hw) * max(0.0, oy) / n_h if n_hw > 0 and n_h > 0 else 0.0
        if sy > floor_y and covered > aref9.get("npc_overlap_max", 0.25):
            err(f"{ctx}.{h.get('id')}: стоянка {h['stand']} прямо перед NPC (ноги {fx:.0f},{fy:.0f}) — Агата закроет "
                f"собой {covered:.0%} фигуры; поставьте стоянку сбоку (видны обе)")

    # 8. рост Агаты против ориентиров
    aref = index.get("agata_ref", {})
    kind = room.get("background", {}).get("kind", "interior")
    dep = room.get("depth", index["defaults"].get("depth_exterior" if kind == "exterior" else "depth", {}))
    for i, hr in enumerate(room.get("height_refs", [])):
        hctx = f"{ctx}.height_refs[{i}] ({hr.get('what', '?')})"
        if not aref:
            err(f"{hctx}: нет agata_ref в _index.json")
            break
        if not all(k in hr for k in ("y", "px", "m")) or hr["px"] <= 0 or hr["m"] <= 0:
            err(f"{hctx}: нужны y, px > 0, m > 0")
            continue
        span = dep["bottom_y"] - dep["top_y"]
        s = dep["scale_top"] + (dep["scale_bottom"] - dep["scale_top"]) * ((hr["y"] - dep["top_y"]) / span if span else 1.0)
        agata = aref["figure_px"] * s
        want = aref["height_m"] * hr["px"] / hr["m"]
        ratio = agata / want
        notes.append(f"{rid}: рост Агаты у «{hr.get('what')}» (y {hr['y']}): {agata:.0f} px при ожидаемых {want:.0f} "
                     f"(scale {s:.3f}, ×{ratio:.2f})")
        if abs(ratio - 1.0) > aref["tolerance"]:
            err(f"{hctx}: рост Агаты {agata:.0f} px (scale {s:.3f}) против ожидаемых {want:.0f} px "
                f"({aref['height_m']} м при {hr['px']} px = {hr['m']} м) — ×{ratio:.2f}, допуск ±{aref['tolerance']:.0%}; "
                f"нужный scale у y {hr['y']} ≈ {want / aref['figure_px']:.3f}")

    for e in room.get("effects", []):
        ectx = f"{ctx}.effects.{e.get('id', e.get('type', '?'))}"
        if e.get("type") not in ("fire", "snow"):
            err(f"{ectx}: неизвестный тип эффекта {e.get('type')}")
        check_flags(ectx + ".if", e.get("if"))
        check_flags(ectx + ".unless", e.get("unless"))
    holes = room.get("walkable_holes", [])
    for i, h in enumerate(holes):
        if len(h) < 3:
            err(f"{ctx}: вырез walkable_holes[{i}] короче 3 точек")
            continue
        if not any(point_in_poly(p, poly) for p in h) and not any(point_in_poly(p, h) for p in poly):
            err(f"{ctx}: вырез walkable_holes[{i}] не пересекает пол — опечатка в координатах?")

    # спавны
    spawns = room.get("spawns", {})
    if "default" not in spawns:
        err(f"{ctx}: нет спавна default")
    def walkable_point(pt) -> bool:
        return point_in_poly(pt, poly) and not any(point_in_poly(pt, h) for h in holes)

    # 6. точки-образцы по картинке
    def in_frame(pt) -> bool:
        return 0 <= pt[0] <= 1920 and 0 <= pt[1] <= 1080

    no_walk = room.get("no_walk_samples", [])
    walk = room.get("walk_samples", [])
    if rid in in_scope:
        if len(no_walk) < 2:
            err(f"{ctx}: нужно ≥ 2 no_walk_samples (точки внутри препятствий/воды), есть {len(no_walk)}")
        if len(walk) < 3:
            err(f"{ctx}: нужно ≥ 3 walk_samples (точки свободного пола), есть {len(walk)}")
    for s in no_walk:
        what = s[2] if len(s) > 2 else ""
        if not in_frame(s):
            err(f"{ctx}: no_walk_sample {s[:2]} вне кадра 1920x1080")
        elif walkable_point(s[:2]):
            err(f"{ctx}: no_walk_sample {s[:2]} ({what}) лежит на полу — Агата пройдёт сквозь препятствие")
    for s in walk:
        if not in_frame(s):
            err(f"{ctx}: walk_sample {s[:2]} вне кадра 1920x1080")
        elif not walkable_point(s[:2]):
            err(f"{ctx}: walk_sample {s[:2]} не на полу (или в вырезе)")
    for nc in room.get("nearest_checks", []):
        frm, box = nc.get("from"), nc.get("in")
        if not frm or not box or len(box) != 4:
            err(f"{ctx}: nearest_checks без from/in[x,y,w,h]: {nc}")
        elif walkable_point(frm):
            err(f"{ctx}: nearest_checks.from {frm} на полу — проверка ближайшей точки бессмысленна")
        elif not any(walkable_point([x, y]) for x in range(int(box[0]), int(box[0] + box[2]) + 1, 5)
                     for y in range(int(box[1]), int(box[1] + box[3]) + 1, 5)):
            err(f"{ctx}: nearest_checks.in {box} не содержит пола")

    for sid, pos in spawns.items():
        if not walkable_point(pos):
            err(f"{ctx}: спавн {sid} {pos} вне полигона (или в вырезе)")

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
        elif not walkable_point(stand):
            err(f"{ctx}: stand выхода в {to} {stand} вне полигона (или в вырезе)")
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

    # хотспот под выходом недостижим кликом, если его pick_priority не выше приоритета выхода (1)
    def _overlap(a, b) -> bool:
        return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]

    for h in room.get("hotspots", []):
        if "rect" not in h:
            continue
        for ex in exits:
            rect, _stand = exit_geometry(room, ex)
            if rect and _overlap(h["rect"], rect) and int(h.get("pick_priority", 0)) <= int(ex.get("pick_priority", 1)):
                err(f"{ctx}.{h.get('id')}: прямоугольник перекрывается выходом в {ex.get('to')} — клик уйдёт выходу (поднимите pick_priority или раздвиньте)")

    # два видимых одновременно хотспота с равным pick_priority не должны перекрываться: Room.pick берёт
    # первый ответ физики, порядок случайный (дефект: shelf под stove в H1 — бот попадал в печь)
    def _exclusive(a, b) -> bool:
        # взаимоисключающие по флагам: один виден при флаге, другой скрыт при том же флаге
        av, ah = set(a.get("visible_if", [])), set(a.get("hidden_if", []))
        bv, bh = set(b.get("visible_if", [])), set(b.get("hidden_if", []))
        return bool(av & bh) or bool(bv & ah)

    hs = [h for h in room.get("hotspots", []) if "rect" in h]
    for i, a in enumerate(hs):
        for b in hs[i + 1:]:
            if _overlap(a["rect"], b["rect"]) and int(a.get("pick_priority", 0)) == int(b.get("pick_priority", 0)) and not _exclusive(a, b):
                err(f"{ctx}: хотспоты {a.get('id')} и {b.get('id')} перекрываются с равным pick_priority — клик непредсказуем (поднимите приоритет меньшему или раздвиньте)")

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
        elif not walkable_point(h["stand"]):
            err(f"{hctx}: stand {h['stand']} вне полигона (или в вырезе)")
        if "image" in h:
            check_res_path(hctx + ".image", h["image"])
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
