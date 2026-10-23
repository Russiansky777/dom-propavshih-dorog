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
  5. геометрия: полигон ≥ 3 точек; точки stand хотспотов/выходов и спавны лежат внутри полигона
     (и stand из states хотспота: состояние может переставить хотспот — rect/stand, H1: Тихон и полка);
     вырезы (walkable_holes) лежат в кадре и пересекают пол;
  6. геометрия по картинке (дефект «Агата проходит сквозь стойку/стол/воду»): у каждой комнаты
     in_scope есть no_walk_samples (≥ 2 точки заведомо внутри препятствий/воды — вне пола или в
     вырезе) и walk_samples (≥ 3 точки свободного пола — на полу и не в вырезе); nearest_checks
     ({from, in:[x,y,w,h]}) — from вне пола. Те же точки проверяет навигацией Godot
     game/tests/test_room_geometry.gd;
     6б. clearance (Z1, Директор 18.10 «Агата чуть да проходит сквозь углы стола»): пол у предмета не ближе
     полуширины Агаты × масштаб глубины к краям его проекции на пол (тело шире ног);
  7. масштаб (Директор: «стул слишком большой, сцена приближена»): фон вписан в 1920x1080 целиком —
     масштаб 1920/ширина ± 0.001, по высоте без обрезки и полос (± 2 px); каждый слой и состояние
     рисуются тем же масштабом (RoomBuilder: art_scale × scale) — scale ≠ 1 только с scale_reason.
     Фактические масштабы узлов сверяет test_room_geometry.gd;
  8. рост Агаты (Директор: «соразмерна дверным проёмам, стойке, партам»): для каждого ориентира
     height_refs комнаты рост Агаты agata_ref.figure_px × scale(y) отличается от
     agata_ref.height_m × px / m не больше чем на agata_ref.tolerance; scale(y) — прямая глубины
     (Room.depth_scale без зажима: ориентиры у стены стоят дальше кромки пола). Таблица — без --quiet.
  9. подсказки выходов (Директор 18.10: «проход в галерею не интуитивен, что нужно нажать вниз»):
     у каждого выхода есть либо метка-шеврон (cue: left/right/down/up или вывод из side / края кадра),
     либо пометка «нарисован в арте» (cue: door). Направление метки у прямоугольника, касающегося края
     кадра, совпадает с этим краем; метка лежит внутри прямоугольника выхода (клик по ней — выход),
     не заходит под верхнюю панель и не сливается с соседней меткой. Выход без cue, выведенный как
     дверь по умолчанию (прямоугольник внутри кадра), — предупреждение «пометьте cue явно».
     Те же правила — ExitCue.classify (game/scripts/rooms/exit_cue.gd), проверка узлов —
     game/tests/test_exit_cues.gd.
     Значок места назначения (Директор 18.10: «значок … мельницы либо дороги … когда наводишь и название
     появляется»): у каждого выхода есть значок — поле icon выхода или таблица _index.json →
     exit_cue.icons по комнате назначения, — и его рисунок game/assets/ui/glyphs/exit_<имя>.svg существует
     (импорт «keep»: .svg.import с importer="keep", иначе игра не прочитает SVG в сборке).
     Курсор над выходом — обычный (большие стрелки-курсоры убраны 18.10): game/tests/test_ui_cursors.gd.
     9б. метка стоит на дороге и смотрит вдоль неё (Директор 23.10, F20: «стрелка „к повороту“ только путает»,
     «спуск к причалу … направить на северо-восток», «в переулок … на середину дороги»): cue_deg (наклон
     метки, градусы экрана: 0 вправо, 90 вниз, −90 вверх) — число в пределах 90° от cue; у выхода, в который
     входят с пола (прямоугольник пересекает пол), метка лежит на полу (или ближе CUE_FLOOR_TOL к нему) и
     точка позади неё (CUE_STEP вдоль метки назад) — тоже, т. е. к метке подходят по полу; метка внутри кадра
     (дорожка вглубь) или с cue_deg смотрит туда же, куда идёт путь от точки прихода (спавн from_<куда>,
     иначе stand) к метке, — не дальше CUE_PATH_DEG. Выход вне пола (люк на чердак, лодка, канат в туман) —
     только направление. Самопроверка: прежняя стрелка Z2 «Спуск к причалу» (вправо) не проходит.
 10. предметы (Директор 18.10: «зачем нам брать предметы, которые нельзя применить»): consumed: true ⇔ где-то
     расходуется; инвентарный предмет E0–E1 применяется в комнатах вехи или объявляет later_use (сцены по
     сценарию) / no_use_reason (спорное, предупреждение); предмет на выходе (exits[].item_use) открывает этот выход.
 11. блок 1 (22.10): слой-заглушка с текстом (layers[].text вместо image: rect, ключ текста); предмет, который берут
     хотспотом без сцены, — только с items.json source_hotspot «<комната>.<хотспот>»; use.restores возвращает
     ранее выданный и израсходованный предмет; выбор с предметом в руке (item_use.choice, варианты consumes_item /
     requires); крупный план «бумаги» (view.pictures / view.photos / view.papers); текст при первом входе (on_enter: text, once_flag);
     сцена N01 и ключ заголовка контрольного сохранения (scenes checkpoint.title).

Код 0 — ошибок нет. Запуск: python3 tools/validate_rooms.py [--quiet]
"""
from __future__ import annotations

import json
import re
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

def tod_flags() -> set[str]:
    """Виртуальные флаги времени суток (F17, game/scripts/core/time_of_day.gd): tod_<состояние>, tod_<фаза>,
    tod_day<N>, tod_dark — их отвечает GameState.has_flag, в сохранение они не пишутся."""
    p = Path(__file__).resolve().parent.parent / "data" / "story" / "time" / "_index.json"
    if not p.exists():
        return set()
    names = {"tod_dark"}
    for s in json.loads(p.read_text(encoding="utf-8")).get("states", []):
        for n in (s.get("id"), s.get("phase"), f"day{s.get('day', 0)}"):
            if n:
                names.add("tod_" + str(n))
    return names


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



def story_flags_of(scene_id: str) -> list[str]:
    """Флаги, которые ставит сцена: её grants, sets её постановок, выборы её реплик."""
    sc = scenes.get(scene_id, {})
    out = list(sc.get("grants", {}).get("flags", []))
    for st in sc.get("stage", []) or []:
        out += list(st.get("sets", []))
    for ln in sc.get("mandatory_lines", []):
        out += [o["sets"] for o in ln.get("options", []) if "sets" in o]
    return out


loc_ids = {l["id"] for l in locations["locations"]}
edges: dict[str, dict[str, list[str]]] = {l: {} for l in loc_ids}
for e in locations["edges"]:
    edges[e["from"]][e["to"]] = list(e["requires"])
    edges[e["to"]][e["from"]] = list(e["requires"])

texts: dict[str, dict] = {}
for tf in sorted(TEXT.glob("*.json")):
    texts.update(load(tf)["texts"])

known_flags: set[str] = set(flags_doc.keys())
known_flags |= tod_flags()   # время суток (F17): виртуальные флаги tod_*
# visited_<комната> ставит сам движок при входе (StoryRunner.on_room_entered): «Агата уже была там» (C13, G21)
known_flags |= {"visited_" + rf_.stem for rf_ in (STORY / "rooms").glob("*.json") if not rf_.stem.startswith("_")}
for sc in scenes.values():
    known_flags |= set(sc.get("grants", {}).get("flags", []))
    for it in sc.get("grants", {}).get("items", []):
        known_flags.add("has_" + it)
    # выбор внутри разговора (M13: ответ Павлу) — mandatory_lines[].options[].sets
    for ln in sc.get("mandatory_lines", []):
        for o in ln.get("options", []):
            if o.get("sets"):
                known_flags.add(o["sets"])
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
                for fl in o.get("also", []) or []:
                    known_flags.add(fl)

for rid in in_scope:
    if rid not in rooms:
        err(f"комната {rid} в in_scope, но файла нет")
    if rid not in loc_ids:
        err(f"комната {rid} не является локацией locations.json")

# 1. локации сцен в объёме вехи
# id сцен не обязательно «буква + две цифры» (день 2: M09s, M13a, M15a, M18p) — список задан явно.
scope_scenes = [s for s in scenes.values() if s["id"] in ("M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "V01", "V02", "V03", "Q04")]
if "N01" in scenes:
    scope_scenes.append(scenes["N01"])   # «Ночь у печи» — конец дня первого (блок 1, 22.10)
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
                     "drawing_label", "error_hint", "text_done", "then"):
                if isinstance(v, list):   # use.text — несколько ключей по очереди (ярлык колокола, затем мысль Агаты)
                    for i, vv in enumerate(v):
                        check_text(f"{ctx}.{k}[{i}]", vv)
                else:
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


CUE_KINDS = ("door", "left", "right", "down", "up")
GLYPHS = ROOT / "game" / "assets" / "ui" / "glyphs"
EXIT_ICONS = (index.get("exit_cue") or {}).get("icons", {})


def exit_icon_problem(ex: dict) -> str:
    """'' если у выхода есть значок с рисунком; иначе — что не так."""
    name = ex.get("icon") or EXIT_ICONS.get(ex.get("to", ""), "")
    if not name:
        return f"нет значка места назначения (поле icon или _index.json → exit_cue.icons[\"{ex.get('to')}\"])"
    svg = GLYPHS / f"exit_{name}.svg"
    if not svg.is_file():
        return f"значок «{name}»: нет рисунка {svg.relative_to(ROOT)}"
    imp = GLYPHS / f"exit_{name}.svg.import"
    if not imp.is_file() or 'importer="keep"' not in imp.read_text(encoding="utf-8"):
        return f"значок «{name}»: {imp.relative_to(ROOT)} должен быть importer=\"keep\" (игра читает SVG сама)"
    return ""
CUE_EDGE_TOL = 8.0          # ExitCue.EDGE_TOL
CUE_EDGE_INSET = 44.0       # ExitCue.EDGE_INSET
CUE_SIDE_MARGIN = 96.0      # ExitCue.SIDE_MARGIN
CUE_TOP_SAFE = 150.0        # ExitCue.TOP_SAFE
CUE_BOTTOM_SAFE = 1010.0    # ExitCue.BOTTOM_SAFE
CUE_HALF_ALONG = 36.0       # полуразмер метки вдоль направления (два шеврона, тень, наклон в подсветке)
CUE_HALF_ACROSS = 44.0      # поперёк направления (ширина шеврона ×1,18 в подсветке, тень)
TOP_BAR = 80.0              # GameUi.TOP_H
CUE_FLOOR_TOL = 60.0        # 9б: метка (и точка позади неё) не дальше этого от пола
CUE_STEP = 80.0             # 9б: шаг вдоль метки назад — «подходят по полу»
CUE_PATH_DEG = 50.0         # 9б: метка вглубь/наклонная смотрит вдоль пути от точки прихода не хуже этого
CUE_PATH_MIN_PX = 100.0     # 9б: ближе — точка прихода у самой метки, направление пути не определено
CUE_ANGLES = {"left": 180.0, "right": 0.0, "up": -90.0, "down": 90.0}


def cue_edges(rect) -> list[str]:
    x, y, w, h = rect
    out = []
    if x <= CUE_EDGE_TOL:
        out.append("left")
    if x + w >= 1920 - CUE_EDGE_TOL:
        out.append("right")
    if y + h >= 1080 - CUE_EDGE_TOL:
        out.append("down")
    return out


def exit_cue(ex: dict, rect):
    """Повторяет ExitCue.classify: (dir, at, source, edges)."""
    edges_ = cue_edges(rect)
    cue = ex.get("cue")
    if cue:
        d, src = cue, "cue"
    else:
        d = {"left": "left", "right": "right", "bottom": "down", "back": "door"}.get(ex.get("side", ""), "")
        src = "side" if d else ""
        if not d:
            if edges_:
                src = "edge"
                if len(edges_) == 1:
                    d = edges_[0]
                elif "down" in edges_:
                    side_edge = "left" if "left" in edges_ else "right"
                    d = side_edge if rect[3] >= rect[2] else "down"
                else:
                    d = edges_[0]
            else:
                d, src = "door", "default"
    cx, cy = rect[0] + rect[2] / 2, rect[1] + rect[3] / 2
    if "cue_at" in ex:
        at = (float(ex["cue_at"][0]), float(ex["cue_at"][1]))
    elif d in edges_:
        if d == "down":
            at = (min(max(cx, CUE_SIDE_MARGIN), 1920 - CUE_SIDE_MARGIN), 1080 - CUE_EDGE_INSET)
        elif d == "left":
            at = (CUE_EDGE_INSET, min(max(cy, CUE_TOP_SAFE), CUE_BOTTOM_SAFE))
        else:
            at = (1920 - CUE_EDGE_INSET, min(max(cy, CUE_TOP_SAFE), CUE_BOTTOM_SAFE))
    else:
        at = (cx, cy)
    return d, at, src, edges_


def _seg_dist(p, a, b) -> float:
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(dx * dx + dy * dy, 1e-9)))
    return ((p[0] - ax - t * dx) ** 2 + (p[1] - ay - t * dy) ** 2) ** 0.5


def floor_dist(pt, poly) -> float:
    """0 на полу, иначе расстояние до кромки полигона."""
    if point_in_poly(pt, poly):
        return 0.0
    return min(_seg_dist(pt, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))


def rects_overlap_poly(rect, poly) -> bool:
    x, y, w, h = rect
    corners = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    if any(point_in_poly(c, poly) for c in corners):
        return True
    return any(x <= p[0] <= x + w and y <= p[1] <= y + h for p in poly)


def cue_path_problems(room: dict, ex: dict, rect, d: str, at, edges_) -> list[str]:
    """9б: метка на дороге и вдоль пути. Пустой список — всё в порядке."""
    import math
    out: list[str] = []
    base = CUE_ANGLES.get(d)
    if base is None:
        return out
    ang = base
    if "cue_deg" in ex:
        if not isinstance(ex["cue_deg"], (int, float)):
            return [f"cue_deg {ex['cue_deg']!r} — число (градусы экрана)"]
        ang = float(ex["cue_deg"])
        if abs((ang - base + 180.0) % 360.0 - 180.0) > 90.0:
            out.append(f"cue_deg {ang:g} дальше 90° от cue «{d}» — поменяйте cue")
    v = (math.cos(math.radians(ang)), math.sin(math.radians(ang)))
    poly = walkable_of(room)
    if rects_overlap_poly(rect, poly):
        dm = floor_dist(at, poly)
        if dm > CUE_FLOOR_TOL:
            out.append(f"метка ({at[0]:.0f}, {at[1]:.0f}) не на дороге: до пола {dm:.0f} px")
        behind = (at[0] - v[0] * CUE_STEP, at[1] - v[1] * CUE_STEP)
        db = floor_dist(behind, poly)
        if db > CUE_FLOOR_TOL:
            out.append(f"к метке не подойти по полу: позади неё ({behind[0]:.0f}, {behind[1]:.0f}) до пола {db:.0f} px — метка смотрит не туда")
    inner = not (d in edges_ and "cue_deg" not in ex)
    if inner:
        arr = (room.get("spawns", {}).get(f"from_{ex.get('to')}") or ex.get("stand"))
        if arr:
            vx, vy = at[0] - arr[0], at[1] - arr[1]
            if (vx * vx + vy * vy) ** 0.5 >= CUE_PATH_MIN_PX:
                pa = math.degrees(math.atan2(vy, vx))
                diff = abs((ang - pa + 180.0) % 360.0 - 180.0)
                if diff > CUE_PATH_DEG:
                    out.append(f"метка смотрит на {ang:g}°, а путь от точки прихода {list(arr)} к ней идёт на {pa:.0f}° (расхождение {diff:.0f}° > {CUE_PATH_DEG:g}°)")
    return out


def _cue_selfcheck() -> None:
    """Прежняя метка Z2 «Спуск к причалу» — вправо из середины прямоугольника — должна не пройти (F20)."""
    room = {"walkable": [[118, 625], [880, 612], [1110, 612], [1240, 622], [1500, 642], [1700, 662], [1915, 738], [1915, 1070], [140, 1070], [140, 800], [118, 790]],
            "spawns": {"from_R1": [1600, 800]}}
    ex = {"to": "R1", "cue": "right", "rect": [1540, 640, 250, 110], "stand": [1600, 780]}
    d, at, _src, edg = exit_cue(ex, ex["rect"])
    if not cue_path_problems(room, ex, ex["rect"], d, at, edg):
        err("validate_rooms 9б: самопроверка не сработала — прежняя стрелка Z2 «Спуск к причалу» (вправо) прошла бы")
    ex_ok = dict(ex, cue_at=[1690, 668], cue_deg=-40)
    d, at, _src, edg = exit_cue(ex_ok, ex_ok["rect"])
    if cue_path_problems(room, ex_ok, ex_ok["rect"], d, at, edg):
        err("validate_rooms 9б: самопроверка — исправленная стрелка Z2 «Спуск к причалу» (северо-восток) не прошла")


SFX_SOUNDS = set(load(STORY / "sfx.json").get("sounds", {}).keys()) if (STORY / "sfx.json").exists() else set()


def check_winter_view(ctx: str, art: dict) -> None:
    """F18 (Директор 23.10: «в проёме просто синий прямоугольник со снегом»): вид в класс за открытой дверью —
    вырезка арта (image есть, region внутри картинки) того же отношения сторон, что проём (±3 %: без искажения)."""
    wv = art.get("winter_view")
    if not wv:
        return
    img = str(wv.get("image", ""))
    size = png_size(img) if img.startswith("res://") else None
    if size is None:
        err(f"{ctx}: нет картинки {img}")
        return
    r = wv.get("region") or []
    if len(r) != 4 or r[2] <= 0 or r[3] <= 0 or r[0] < 0 or r[1] < 0 or r[0] + r[2] > size[0] or r[1] + r[3] > size[1]:
        err(f"{ctx}: region {r} вне картинки {size[0]}×{size[1]}")
        return
    op = art.get("opening") or []
    if len(op) == 4 and op[3] > 0:
        a, b = r[2] / r[3], op[2] / op[3]
        if abs(a / b - 1.0) > 0.03:
            err(f"{ctx}: отношение сторон вырезки {a:.3f} ≠ проёма {b:.3f} — класс в проёме будет растянут")


def check_match_marks_mouse(ctx: str, pz: dict) -> None:
    """Крупный план match_marks мышью (closeup_puzzle.gd, Директор 18.10): гнёзда — разные точки дальше
    двух радиусов защёлкивания друг от друга (иначе петля «прилипает» не туда); число деталей = набор
    предмета (items.json set_count); у бруса есть метка двери anchor, при start_shift ни одна зарубка не
    стоит под ней, а верную можно подвести в пределах shift_range; звуки — из sfx.json."""
    snap = float(pz.get("drag", {}).get("snap_px", 60))
    slots = pz.get("slots", [])
    for i, a in enumerate(slots):
        for b in slots[i + 1:]:
            d = ((a["pos"][0] - b["pos"][0]) ** 2 + (a["pos"][1] - b["pos"][1]) ** 2) ** 0.5
            if d <= 2 * snap:
                err(f"{ctx}: гнёзда {a['id']} и {b['id']} ближе 2×snap_px ({d:.0f} ≤ {2 * snap:.0f})")
    for it in pz.get("requires", {}).get("items", []):
        n = items.get(it, {}).get("set_count")
        if n is not None and n != len(pz.get("pieces", [])):
            err(f"{ctx}: деталей {len(pz.get('pieces', []))}, а в наборе {it} (items.json set_count) — {n}")
    mk = pz.get("marks", {})
    pos = mk.get("positions", [])
    if "anchor" in mk and pos:
        ax = mk["anchor"][0]
        msnap = float(mk.get("snap_px", 40))
        start = float(mk.get("start_shift", 0))
        lo, hi = mk.get("shift_range", [-1e9, 1e9])
        for i, p in enumerate(pos):
            if abs(p[0] + start - ax) <= msnap:
                err(f"{ctx}.marks: при start_shift {start:.0f} зарубка {i} уже под меткой двери — загадка решена до начала")
        need = ax - pos[mk.get("correct", 0)][0]
        if not (lo <= need <= hi):
            err(f"{ctx}.marks: верную зарубку не подвести под метку: нужен сдвиг {need:.0f}, shift_range {lo}..{hi}")
    for k, sid in (pz.get("sounds") or {}).items():
        if not k.startswith("_") and SFX_SOUNDS and sid not in SFX_SOUNDS:
            err(f"{ctx}.sounds.{k}: звука {sid} нет в sfx.json (новых звуков не заводим)")


def check_view(ctx: str, v: dict) -> None:
    """Крупный план «посмотреть» (closeup_view.gd): зеркало — 4 угла стекла внутри картинки фона, стекло
    и поля положительные; снимок — область внутри картинки; тексты есть."""
    for key in ("title", "close_label"):
        if key in v:
            check_text(f"{ctx}.{key}", v[key])
    if v.get("type") == "mirror":
        fr = v.get("frame", {})
        check_res_path(ctx + ".frame.image", fr.get("image", ""))
        size = png_size(fr.get("image", ""))
        quad = fr.get("glass_quad", [])
        if len(quad) != 4:
            err(f"{ctx}.frame.glass_quad: нужно 4 угла стекла")
        elif size:
            for p in quad:
                if not (0 <= p[0] <= size[0] and 0 <= p[1] <= size[1]):
                    err(f"{ctx}.frame.glass_quad: угол {p} вне картинки {size}")
        if any(x <= 0 for x in fr.get("glass", [0, 0])):
            err(f"{ctx}.frame.glass: размеры стекла должны быть > 0")
        ag = v.get("reflection", {}).get("agata", {})
        if not (0 <= int(ag.get("row", 0)) < 8):
            err(f"{ctx}.reflection.agata.row: строка листа 0..7")
    if "photo" in v:
        ph = v["photo"]
        check_res_path(ctx + ".photo.image", ph.get("image", ""))
        size = png_size(ph.get("image", ""))
        r = ph.get("region", [])
        if len(r) != 4 or r[2] <= 0 or r[3] <= 0:
            err(f"{ctx}.photo.region: нужно [x, y, w, h]")
        elif size and (r[0] < 0 or r[1] < 0 or r[0] + r[2] > size[0] or r[1] + r[3] > size[1]):
            err(f"{ctx}.photo.region {r} вне картинки {size}")
        if "label" in ph:
            check_text(ctx + ".photo.label", ph["label"])


EFFECT_TYPES = ("fire", "snow", "tint", "shapes", "rope")
BLENDS = ("mul", "add", "sub", "mix")
SHAPE_TYPES = ("gradient", "poly", "line", "circle", "glow", "text", "rect", "dashes")
MECHANIC_TYPES = ("office_mirror", "sluice", "fast_mirror", "plate", "lantern", "photo", "windlass", "latch", "crossing",
                  "tracing", "workbench")

# 13. Арт заказан и ещё не доставлен (партия 8б, Q02/Q06, 23.10): слой или картинка крупного плана с `pending` — id
# заявки assets/manifest.json. Пока заявка открыта (requested / in_progress), файла может не быть: вместо картинки
# движок строит `stub` (PlaceholderArt.stand_in). Файл заявки должен быть в её files — тогда смена заглушки на арт —
# один импорт (tools/import_room_art.py для слоёв комнат и кадров — по art_source.files; tools/import_closeups.py —
# крупные планы game/assets/closeups/<имя>.png ← assets/incoming/<имя>.png).
_MANIFEST_PATH = ROOT / "assets" / "manifest.json"
MANIFEST_REQ = {r.get("id"): r for r in (load(_MANIFEST_PATH).get("requests", []) if _MANIFEST_PATH.exists() else [])}
PENDING_OPEN = ("requested", "in_progress")


def check_pending(ctx: str, pending_id, res: str, incoming: str | None, stub) -> bool:
    """Картинка `res` заказана (`pending`). True — файла ещё нет и это законно (заглушка вместо него)."""
    r = MANIFEST_REQ.get(pending_id)
    if r is None:
        err(f"{ctx}: pending {pending_id} — нет такой заявки в assets/manifest.json")
        return False
    if res.startswith("res://") and (GAME_DIR / res[len("res://"):]).exists():
        if r.get("status") in PENDING_OPEN:
            warn(f"{ctx}: {res} уже в игре, а заявка {pending_id} — {r.get('status')} (отметьте delivered; pending/stub можно убрать)")
        return False
    if r.get("status") not in PENDING_OPEN:
        err(f"{ctx}: файла {res} нет, а заявка {pending_id} — {r.get('status')}: импортируйте арт")
    if incoming is None:
        err(f"{ctx}: заказанный файл {res} не связан с поставкой (art_source.files комнаты) — импорт его не положит")
    elif incoming not in r.get("files", []):
        err(f"{ctx}: {incoming} нет в заявке {pending_id} (assets/manifest.json → files)")
    if not isinstance(stub, dict) or not (stub.get("shapes") or stub.get("crops") or stub.get("texts")):
        err(f"{ctx}: нет stub — заглушки движка до арта (shapes / crops / texts)")
    return True


def check_stub(ctx: str, stub) -> None:
    """Заглушка движка (PlaceholderArt.stand_in): фигуры известны, вырезки — из картинок игры, тексты — ключи."""
    if not isinstance(stub, dict):
        return
    check_shapes(ctx + ".shapes", stub.get("shapes"))
    for i, c in enumerate(stub.get("crops", []) or []):
        check_res_path(f"{ctx}.crops[{i}].image", c.get("image", ""))
        if len(c.get("region", [])) != 4:
            err(f"{ctx}.crops[{i}].region: [x, y, w, h] в пикселях картинки")
    for i, t in enumerate(stub.get("texts", []) or []):
        check_text(f"{ctx}.texts[{i}].text", t.get("text", ""))
        if len(t.get("rect", [])) != 4:
            err(f"{ctx}.texts[{i}].rect: [x, y, w, h]")


def check_shapes(ctx: str, shapes) -> None:
    """Фигуры заглушек (PlaceholderArt): тип известен, у многоугольника ≥ 3 точек, тексты есть."""
    for i, sh in enumerate(shapes or []):
        t = sh.get("type")
        if t not in SHAPE_TYPES:
            err(f"{ctx}[{i}]: тип {t} — есть {', '.join(SHAPE_TYPES)}")
        if t == "poly" and len(sh.get("points", [])) < 3:
            err(f"{ctx}[{i}]: poly короче 3 точек")
        if t == "line" and len(sh.get("points", [])) < 2:
            err(f"{ctx}[{i}]: line короче 2 точек")
        if t == "text":
            check_text(f"{ctx}[{i}].text", sh.get("text", ""))


def check_knot_around_ring(ctx: str, m: dict) -> None:
    """G27 (Директор 23.10: узел «будто в воздухе, а не вокруг кольца»): путь узла идёт по нарисованному кольцу
    (`ring` центр, `ring_r_in`…`ring_r` — тело кольца, пиксели холста). Первое движение начинается снаружи кольца и
    кончается в его просвете, проходя под телом в нижней дуге, которую плита рисует поверх каната (`ring_front_deg`);
    второе выходит из просвета поверх тела и идёт вокруг по внешнему краю — не дальше 1,35 наружного радиуса и дугой
    не меньше 30°; ни одна точка первых двух движений не уходит от кольца дальше 1,35 наружного радиуса, кроме начала."""
    import math
    kp = m.get("knot_path", {})
    st = kp.get("strokes", [])
    if len(st) < 2 or "ring" not in m:
        return
    cx, cy = float(m["ring"][0]), float(m["ring"][1])
    r_out = float(m.get("ring_r", 158))
    r_in = float(m.get("ring_r_in", 98))
    front = m.get("ring_front_deg", [12, 168])

    def polar(q):
        dx, dy = float(q[0]) - cx, float(q[1]) - cy
        return math.hypot(dx, dy), math.degrees(math.atan2(dy, dx)) % 360.0

    s1 = [polar(q) for q in st[0]]
    if s1[0][0] <= r_out:
        err(f"{ctx}.knot_path.strokes[0]: конец каната должен лежать снаружи кольца (r {s1[0][0]:.0f} ≤ {r_out:.0f})")
    if s1[-1][0] >= r_in:
        err(f"{ctx}.knot_path.strokes[0]: «под кольцо и вверх в него» кончается в просвете кольца (r {s1[-1][0]:.0f} ≥ {r_in:.0f})")
    under = [a for r, a in s1 if r_in <= r <= r_out]
    if not under or not all(float(front[0]) <= a <= float(front[1]) for a in under):
        err(f"{ctx}.knot_path.strokes[0]: под телом кольца путь идёт в нижней дуге {front} (там плита рисуется поверх каната), углы {[round(a) for a in under]}")
    for i, (r, a) in enumerate(s1[1:], 1):
        if r > r_out * 1.35 and i >= len(s1) - 4:
            err(f"{ctx}.knot_path.strokes[0][{i}]: у кольца путь не дальше 1,35 наружного радиуса (r {r:.0f})")
    s2 = [polar(q) for q in st[1]]
    if s2[0][0] >= r_in:
        err(f"{ctx}.knot_path.strokes[1]: «вокруг» начинается в просвете кольца (r {s2[0][0]:.0f})")
    far = [round(r) for r, _ in s2 if r > r_out * 1.35]
    if far:
        err(f"{ctx}.knot_path.strokes[1]: «вокруг» по контуру кольца — не дальше {r_out * 1.35:.0f} px от центра, есть {far} (G27: петля в воздухе)")
    outside = [a for r, a in s2 if r >= r_out]
    if not outside or max(outside) - min(outside) < 30.0:
        err(f"{ctx}.knot_path.strokes[1]: «вокруг» идёт по внешнему краю кольца дугой ≥ 30° (есть {[round(a) for a in outside]})")


def check_mechanic(ctx: str, m: dict, room: dict) -> None:
    """Крупный план-механика дня 2 (game/scripts/mechanics/*): тип известен; флаги условий и событий известны;
    тексты texts.* есть; картинки (любое поле image/icon) есть в game/; same_as ссылается на хотспот с механикой."""
    if "same_as" in m:
        other = next((h for h in room.get("hotspots", []) if h.get("id") == m["same_as"]), None)
        if other is None or "mechanic" not in other:
            err(f"{ctx}.same_as: нет хотспота {m['same_as']} с mechanic в {room.get('id')}")
        return
    if m.get("type") not in MECHANIC_TYPES:
        err(f"{ctx}: тип {m.get('type')} — есть {', '.join(MECHANIC_TYPES)}")
    check_flags(ctx + ".requires", m.get("requires", {}).get("flags"))
    check_items(ctx + ".requires", m.get("requires", {}).get("items"))
    for k, v in (m.get("texts") or {}).items():
        check_text(f"{ctx}.texts.{k}", v)
    for name, ev in (m.get("events") or {}).items():
        check_flags(f"{ctx}.events.{name}.sets", ev.get("sets"))
        check_text(f"{ctx}.events.{name}.text", ev.get("text", ""))
    for key in ("clamped_flag", "done_flag", "compared_flag", "common_time_flag"):
        if key in m:
            check_flags(f"{ctx}.{key}", [m[key]])

    def images(o, path):
        if isinstance(o, dict):
            for k, v in o.items():
                if (k in ("image", "icon", "watch_icon") or (isinstance(v, str) and v.startswith("res://"))) and isinstance(v, str):
                    # 13. заказанный крупный план (pending): game/assets/closeups/<имя>.png ← assets/incoming/<имя>.png
                    if m.get("pending") and path.startswith(ctx + ".art") and v.startswith("res://assets/closeups/") \
                            and check_pending(f"{path}.{k}", m["pending"], v, "incoming/" + Path(v).name, m.get("stub")):
                        continue
                    check_res_path(f"{path}.{k}", v)
                else:
                    images(v, f"{path}.{k}")
        elif isinstance(o, list):
            for i, v in enumerate(o):
                if isinstance(v, str) and v.startswith("res://"):
                    check_res_path(f"{path}[{i}]", v)
                else:
                    images(v, f"{path}[{i}]")
    images(m, ctx)
    # Арт партии 3 (22.10) вместо заглушек движка: у каждого крупного плана — свои картинки (их пути проверены выше).
    need = {"office_mirror": [("frame", "images"), ("office", "art", "bg"), ("office", "art", "light"), ("office", "art", "hook"), ("office", "art", "bar")],
            "fast_mirror": [("room_art", k) for k in ("bg", "clock_face", "pendulum", "hand_min", "hand_hour", "flame")],
            "plate": [("art", "bg"), ("art", "skoba"), ("art", "rope")],
            "lantern": [("art", "closed"), ("art", "open")],
            "photo": [("photo", "image")]}
    for keys in need.get(m.get("type"), []):
        o = m
        for kk in keys:
            o = o.get(kk) if isinstance(o, dict) else None
        if not o:
            err(f"{ctx}.{'.'.join(keys)}: нет картинки крупного плана (арт партии 3 вместо заглушки движка)")
    # Mechanics of 23.10 (F6–F8, F12): the «точный удар» bar, the knot path, the latch, the crossing.
    tm = m.get("timing")
    if tm is not None:
        if not 1 <= int(tm.get("hits", 1)) <= 5:
            err(f"{ctx}.timing.hits: 1–5 попаданий подряд, есть {tm.get('hits')}")
        if not 0.08 <= float(tm.get("green", 0.2)) <= 0.5:
            err(f"{ctx}.timing.green: зелёная зона 0.08–0.5 полосы (честно и не даром), есть {tm.get('green')}")
        check_text(f"{ctx}.timing.hint", tm.get("hint", ""))
    if m.get("type") == "plate":
        kp = m.get("knot_path", {})
        if len(kp.get("strokes", [])) < 2 or any(len(st) < 2 for st in kp.get("strokes", [])):
            err(f"{ctx}.knot_path.strokes: узел — 2–3 движения по ≥ 2 точки (F6)")
        for i, lb in enumerate(kp.get("labels", [])):
            check_text(f"{ctx}.knot_path.labels[{i}]", lb)
        if "timing" not in m:
            err(f"{ctx}.timing: скоба забивается «точным ударом» (F7)")
        check_knot_around_ring(ctx, m)
    if m.get("type") == "latch":
        for kk in ("closed", "open"):
            if not m.get("art", {}).get(kk):
                err(f"{ctx}.art.{kk}: нет картинки ставни")
    if m.get("type") == "crossing":
        for kk in ("bg", "rope", "arrival"):
            if not m.get("art", {}).get(kk):
                err(f"{ctx}.art.{kk}: нет картинки переправы")
        if not 5 <= int(m.get("pulls", 10)) <= 20:
            err(f"{ctx}.pulls: около 10 перехватов (F12), есть {m.get('pulls')}")
    if "stub" in m:
        check_stub(ctx + ".stub", m["stub"])
    if m.get("type") == "tracing":
        # Q02: «протянуть по контуру» по кальке — линии в долях участка plot (0..1), подпись у каждой; фаза кальки по флагам.
        lines = m.get("lines", {})
        st_ = lines.get("strokes", [])
        if len(st_) < 2 or any(len(x) < 2 for x in st_):
            err(f"{ctx}.lines.strokes: 2–4 линии по ≥ 2 точки")
        for i, x in enumerate(st_):
            if any(not (0.0 <= float(q[0]) <= 1.0 and 0.0 <= float(q[1]) <= 1.0) for q in x):
                err(f"{ctx}.lines.strokes[{i}]: точки — доли участка plot, 0..1")
        if len(lines.get("labels", [])) != len(st_):
            err(f"{ctx}.lines.labels: подпись у каждой линии ({len(st_)})")
        for i, lb in enumerate(lines.get("labels", [])):
            check_text(f"{ctx}.lines.labels[{i}]", lb)
        if len(m.get("plot", [])) != 4:
            err(f"{ctx}.plot: [x, y, w, h] — участок на холсте 1672×941")
        check_flags(ctx + ".trace_when", m.get("trace_when"))
        if not m.get("trace_when") or not m.get("done_flag"):
            err(f"{ctx}: trace_when (когда калька) и done_flag (линии проведены)")
        if m.get("done_flag") not in (m.get("events", {}).get("traced", {}).get("sets") or []):
            err(f"{ctx}.events.traced: ставит done_flag {m.get('done_flag')}")
        if m.get("done_flag") not in (m.get("unless") or []):
            err(f"{ctx}.unless: после линий крупный план не открывается снова (done_flag)")
    if m.get("type") == "workbench":
        # Q06: четыре шага — флаги steps ставят события fitted / stopped / tightened / checked по порядку.
        steps_ = m.get("steps", [])
        if len(steps_) != 4:
            err(f"{ctx}.steps: четыре флага шагов (паз, ограничитель, винт, доска)")
        for name, fl in zip(("fitted", "stopped", "tightened", "checked"), steps_):
            if fl not in (m.get("events", {}).get(name, {}).get("sets") or []):
                err(f"{ctx}.events.{name}: ставит флаг шага {fl}")
        fa = m.get("parts", {}).get("fastenings", [])
        if len(fa) < 2 or sum(1 for f in fa if f.get("fits")) != 1:
            err(f"{ctx}.parts.fastenings: два и больше креплений, в паз садится ровно одно (fits)")
        for i, f in enumerate(fa):
            check_text(f"{ctx}.parts.fastenings[{i}].label", f.get("label", ""))
            check_text(f"{ctx}.parts.fastenings[{i}].text", f.get("text", ""))
        if "timing" not in m:
            err(f"{ctx}.timing: винт затягивается «точным ударом»")
        if steps_ and steps_[-1] not in (m.get("unless") or []):
            err(f"{ctx}.unless: собранный верстак крупным планом не открывается снова ({steps_[-1] if steps_ else '?'})")
    if m.get("type") == "office_mirror" and len(m.get("frame", {}).get("glass_polygon", [])) != 4:
        err(f"{ctx}.frame.glass_polygon: контур стекла — 4 точки холста (glass_polygon_px поставки)")
    if m.get("type") == "office_mirror":
        # G19: клинья — нарисованные (loose / half / driven), каждый по своей рамке внутри кадра рамы; три удара «точного удара».
        ws = m.get("wedges", {})
        reg = m.get("frame", {}).get("region", [0, 0, 0, 0])
        if not isinstance(ws, dict) or not ws.get("boxes"):
            err(f"{ctx}.wedges: клинья — {{art: {{loose, half, driven}}, boxes: [[x, y, w, h], …], timing}} (G19)")
        else:
            for k in ("loose", "half", "driven"):
                if not ws.get("art", {}).get(k):
                    err(f"{ctx}.wedges.art.{k}: нет слоя клиньев")
            for i, b in enumerate(ws["boxes"]):
                if len(b) != 4 or not (reg[0] <= b[0] and b[0] + b[2] <= reg[0] + reg[2] and reg[1] <= b[1] and b[1] + b[3] <= reg[1] + reg[3]):
                    err(f"{ctx}.wedges.boxes[{i}]: рамка клина {b} вне кадра рамы {reg}")
            if int(ws.get("timing", {}).get("hits", 0)) != 3:
                err(f"{ctx}.wedges.timing.hits: каждый клин — три удара (G19)")
    if m.get("type") == "fast_mirror":
        if float(m.get("ratio", 20)) != 20.0:
            err(f"{ctx}.ratio: время внутри идёт ровно в 20 раз быстрее (канон, SCENARIO_FINAL §4.3) — {m.get('ratio')}")
        if len(m.get("poses", [])) < 5:
            err(f"{ctx}.poses: нужно 5–6 поз Нины, есть {len(m.get('poses', []))}")


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
    # 12. кадр (блоки 3–4, "frame": true): картина поверх мира для FrameView — не локация, без ходьбы, хотспотов и
    # выходов; Агаты в кадре нет (player_hidden). Остальные проверки (фон, масштаб, слои, тексты) — как у комнат.
    if room.get("frame"):
        if rid in loc_ids or rid in in_scope:
            err(f"{ctx}: кадр не может быть локацией или комнатой in_scope")
        if room.get("hotspots") or room.get("exits"):
            err(f"{ctx}: у кадра нет хотспотов и выходов")
        if not room.get("player_hidden"):
            err(f"{ctx}: кадр без player_hidden: true")
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
        # 7в. Состояние, нарисованное другим кадром, совмещено с основой (G13, Директор 23.10: «топящаяся печь
        # разорвана» — рама открытой дверцы стояла на 80 px выше закрытой дверцы фона и на четверть крупнее):
        # `align` {layer_rect — деталь в пикселях слоя, base_rect — та же деталь в пикселях фона, tol_px, covers}.
        # На экране низ, левый и правый край детали совпадают в пределах tol_px; covers — деталь слоя закрывает деталь
        # фона целиком (иначе из-под неё торчит старое состояние). Пиксели сверяет game/tests/test_h1.gd.
        al = l.get("align")
        if al is not None and bg_scale:
            try:
                lr = [float(v) for v in al["layer_rect"]]
                br = [float(v) for v in al["base_rect"]]
                tol = float(al.get("tol_px", 12))
                off = [float(v) for v in l.get("offset", [0, 0])]
                k = bg_scale * sc
                lx0, ly0 = off[0] + lr[0] * k, off[1] + lr[1] * k
                lx1, ly1 = lx0 + lr[2] * k, ly0 + lr[3] * k
                bx0, by0 = br[0] * bg_scale, br[1] * bg_scale
                bx1, by1 = bx0 + br[2] * bg_scale, by0 + br[3] * bg_scale
                if abs(ly1 - by1) > tol:
                    err(f"{lctx}.align: низ детали слоя {ly1:.0f} ≠ низ на фоне {by1:.0f} (±{tol:.0f} px экрана)")
                if abs((lx0 + lx1) / 2 - (bx0 + bx1) / 2) > tol:
                    err(f"{lctx}.align: середина детали слоя x {(lx0 + lx1) / 2:.0f} ≠ на фоне {(bx0 + bx1) / 2:.0f} (±{tol:.0f})")
                if abs((lx1 - lx0) - (bx1 - bx0)) > 2 * tol or abs((ly1 - ly0) - (by1 - by0)) > 2 * tol:
                    err(f"{lctx}.align: размер детали слоя {lx1 - lx0:.0f}×{ly1 - ly0:.0f} ≠ на фоне {bx1 - bx0:.0f}×{by1 - by0:.0f}")
                if al.get("covers"):
                    # непрозрачная часть слоя вокруг детали (cover_rect, пиксели слоя; по умолчанию сама деталь) закрывает
                    # деталь фона целиком (±4 px); что cover_rect на слое и правда непрозрачен — сверяет test_h1 по пикселям
                    cr = [float(v) for v in al.get("cover_rect", al["layer_rect"])]
                    cx0, cy0 = off[0] + cr[0] * k, off[1] + cr[1] * k
                    cx1, cy1 = cx0 + cr[2] * k, cy0 + cr[3] * k
                    if cx0 > bx0 + 4 or cx1 < bx1 - 4 or cy0 > by0 + 4 or cy1 < by1 - 4:
                        err(f"{lctx}.align: слой [{cx0:.0f}..{cx1:.0f}]×[{cy0:.0f}..{cy1:.0f}] не закрывает деталь фона "
                            f"[{bx0:.0f}..{bx1:.0f}]×[{by0:.0f}..{by1:.0f}] — из-под него видно прежнее состояние")
            except (KeyError, TypeError, ValueError, IndexError):
                err(f"{lctx}.align: нужны layer_rect и base_rect [x, y, w, h]")
        if sc <= 0:
            err(f"{lctx}: scale {sc} ≤ 0")
        if "image" not in l and "text" in l:
            # заглушка до арта: надпись шрифтом игры (O1: мелом на доске «Мама, я иду» / «Илюша…», блок 1)
            r_ = l.get("rect", [])
            if len(r_) != 4 or r_[2] <= 0 or r_[3] <= 0:
                err(f"{lctx}: текстовый слой без rect [x, y, w, h]")
            if not str(l["text"]).startswith("@"):
                err(f"{lctx}: текст слоя — ключ @… из data/story/text")
            if not str(l.get("_stub", "")).strip():
                warn(f"{lctx}: текстовый слой без _stub — укажите, какой рисунок он заменяет (заявка в assets/manifest.json)")
        elif "image" not in l:
            err(f"{lctx}: нет image")
        elif l.get("pending") and check_pending(
                lctx, l["pending"], l["image"],
                (lambda src: src[len("assets/"):] if src and src.startswith("assets/") else src)(
                    room.get("art_source", {}).get("files", {}).get(Path(l["image"]).name)
                    if l["image"].startswith(f"res://assets/rooms/{rid}/") else None),
                l.get("stub")):
            check_stub(lctx + ".stub", l.get("stub"))
        else:
            if "stub" in l:
                check_stub(lctx + ".stub", l.get("stub"))
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

    def npc_variants(h: dict, actor: dict | None):
        """(rect, stand, place) для каждого места NPC: кукла с place.<LOC>-списком (флаги if/unless, H1 Тихон:
        кресло → полка A / полка B) берёт rect/stand из states хотспота с теми же if-флагами (без if — базовые)."""
        pl = (actor or {}).get("place", {}).get(rid) if (actor or {}).get("type") == "puppet" else None
        if not isinstance(pl, list):
            return [(h["rect"], h["stand"], pl)]
        out = []
        for e in pl:
            fl = sorted(e.get("if", []))
            st = next((s for s in h.get("states", []) if sorted(s.get("if", [])) == fl), None) if fl else None
            if fl and st is None:
                err(f"{ctx}.{h.get('id')}: место куклы с if {fl} (game/data/actors/{h.get('id')}.json place.{rid}) — "
                    f"нет состояния хотспота с теми же флагами (rect/stand)")
                continue
            check_flags(f"{ctx}.{h.get('id')}.place.if", e.get("if"))
            check_flags(f"{ctx}.{h.get('id')}.place.unless", e.get("unless"))
            out.append(((st or {}).get("rect", h["rect"]), (st or {}).get("stand", h["stand"]), e))
        return out

    def check_npc_stand(h, actor, r, stand9, place, hw, fig) -> None:
        sx, sy = stand9
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
            err(f"{ctx}.{h.get('id')}: стоянка {list(stand9)} прямо перед NPC (ноги {fx:.0f},{fy:.0f}) — Агата закроет "
                f"собой {covered:.0%} фигуры; поставьте стоянку сбоку (видны обе)")

    for h in room.get("hotspots", []):
        if h.get("kind") != "npc" or "rect" not in h or "stand" not in h or not aref9.get("figure_half_width_px"):
            continue
        actor_path = GAME_DIR / "data" / "actors" / f"{h.get('id')}.json"
        actor = load(actor_path) if actor_path.exists() else None
        if actor is None and "image" not in h:
            continue  # фигуры нет — закрывать нечего
        for r, stand9, place in npc_variants(h, actor):
            check_npc_stand(h, actor, r, stand9, place, aref9["figure_half_width_px"], aref9["figure_px"])

    # 9b. Стоянки предметов и точки входа не ставят Агату в фигуру NPC (дефект O3 23.10: у ходиков и стола Агата
    # стояла внутри Нины — две фигуры одна в другой). Кто ближе к зрителю, закрывает того, кто дальше; если закрыто
    # больше npc_overlap_max его рамки — ошибка. Предмет и NPC, которые не видны вместе (visible_if одного ∩ hidden_if
    # другого), не сравниваются; куклы (place.<LOC>) — своей проверкой выше.
    if aref9.get("figure_half_width_px"):
        hw0, fig0 = aref9["figure_half_width_px"], aref9["figure_px"]
        npcs9b = []
        for h in room.get("hotspots", []):
            if h.get("kind") != "npc" or "rect" not in h:
                continue
            actor_path = GAME_DIR / "data" / "actors" / f"{h.get('id')}.json"
            actor = load(actor_path) if actor_path.exists() else None
            if (actor is None and "image" not in h) or (actor or {}).get("type") == "puppet":
                continue
            if h.get("scene_only"):
                # Виден только внутри сцены без управления (O3: Илья, Ульяна, жена Ильи — M20): Агата не ходит к
                # стоянкам, пока он виден. Флаги его видимости — из этой сцены.
                sc_only = str(h["scene_only"])
                if not set(h.get("visible_if", [])) <= {f"started_{sc_only}"} | set(story_flags_of(sc_only)):
                    err(f"{ctx}.{h.get('id')}: scene_only {sc_only}, но visible_if {h.get('visible_if')} не из этой сцены")
                continue
            r = h["rect"]
            factor = float((actor or {}).get("npc", {}).get("scale_factor", 1.0))
            npcs9b.append((h, r[0] + r[2] / 2, r[1] + r[3], factor))

        def apart(a: dict, b: dict) -> bool:
            return bool(set(a.get("visible_if", [])) & set(b.get("hidden_if", []))) or \
                bool(set(b.get("visible_if", [])) & set(a.get("hidden_if", [])))

        places9b = [(f"hotspots.{h.get('id')}.stand", h, h["stand"]) for h in room.get("hotspots", [])
                    if h.get("kind") != "npc" and "stand" in h]
        # spawns.default — запасная точка (входы и постановки называют свою), её не сравниваем.
        places9b += [(f"spawns.{sid}", {}, pos) for sid, pos in room.get("spawns", {}).items() if sid != "default"]
        # Комнаты-исключения (_index.json agata_ref.npc_overlap_warn_rooms: стоянки правит владелец комнаты) —
        # предупреждение вместо ошибки, пока их не поправят.
        report9b = warn if rid in aref9.get("npc_overlap_warn_rooms", []) else err
        for where, src, (sx, sy) in places9b:
            a_s = depth_scale(sy)
            a_hw, a_h = hw0 * a_s, fig0 * a_s
            for nh, fx, fy, factor in npcs9b:
                if apart(src, nh):
                    continue
                n_s = depth_scale(fy) * factor
                n_hw, n_h = hw0 * n_s, fig0 * n_s
                ox = min(sx + a_hw, fx + n_hw) - max(sx - a_hw, fx - n_hw)
                oy = min(sy, fy) - max(sy - a_h, fy - n_h)
                if ox <= 0 or oy <= 0:
                    continue
                behind_hw, behind_h, who = (n_hw, n_h, f"NPC {nh.get('id')}") if sy > fy else (a_hw, a_h, "Агату")
                covered = ox / (2 * behind_hw) * oy / behind_h
                if covered > aref9.get("npc_overlap_max", 0.25):
                    report9b(f"{ctx}.{where} {[sx, sy]}: Агата и NPC {nh.get('id')} (ноги {fx:.0f},{fy:.0f}) — одна фигура в другой: "
                        f"закрыто {covered:.0%} фигуры ({who}); сдвиньте стоянку или NPC")
        # Нарисованный предмет (слой с id своего хотспота) не стоит за фигурой NPC: O4 — Митя стоял прямо перед своей
        # дощечкой партии 8 и закрывал её (23.10). Предмет за фигурой (низ выше ног NPC) закрыт больше чем наполовину — ошибка.
        layer_ids9c = {str(l.get("id")) for l in room.get("layers", [])}
        for oh in room.get("hotspots", []):
            if oh.get("kind") == "npc" or str(oh.get("id")) not in layer_ids9c or "rect" not in oh:
                continue
            ox0, oy0, ow, oh_h = oh["rect"]
            for nh, fx, fy, factor in npcs9b:
                if apart(oh, nh) or oy0 + oh_h >= fy:
                    continue
                n_s = depth_scale(fy) * factor
                n_hw, n_h = hw0 * n_s, fig0 * n_s
                cx = min(ox0 + ow, fx + n_hw) - max(ox0, fx - n_hw)
                cy = min(oy0 + oh_h, fy) - max(oy0, fy - n_h)
                if cx > 0 and cy > 0 and cx * cy / float(ow * oh_h) > 0.5:
                    err(f"{ctx}.hotspots.{oh.get('id')}: нарисованный предмет {oh['rect']} за фигурой NPC {nh.get('id')} "
                        f"(ноги {fx:.0f},{fy:.0f}) — закрыт на {cx * cy / float(ow * oh_h):.0%}; сдвиньте NPC")

    # 8. рост Агаты против ориентиров
    # Каждая комната с Агатой в кадре сверяет её рост с дверью: ориентир с "door": true или явно "door_ref": "none — почему"
    # (координатор 23.10: чтобы проверка не пропустила комнату молча).
    if not room.get("frame") and not room.get("player_hidden") or rid == "R2":
        n_door = sum(1 for hr in room.get("height_refs", []) if hr.get("door"))
        dref = str(room.get("door_ref", ""))
        if n_door == 0 and not dref.startswith("none"):
            err(f"{ctx}: нет ориентира двери (height_refs … \"door\": true) и нет \"door_ref\": \"none — почему\"")
        if n_door and dref:
            err(f"{ctx}: и дверь-ориентир, и door_ref «{dref}» — оставьте одно")
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
        # D3 (ИИ-плейтест 22.10, координатор 23.10): у порога двери Агата — 0,85–0,95 высоты двери на фоне, по прямой
        # глубины (порог за краем пола — продолжение прямой, как у ориентиров выше). Ориентир с "door": true.
        if hr.get("door"):
            if not 0.85 <= agata / hr["px"] <= 0.95:
                err(f"{hctx}: у порога двери Агата {agata:.0f} px — {agata / hr['px']:.2f} высоты двери ({hr['px']} px), нужно 0,85–0,95")

    for e in room.get("effects", []):
        ectx = f"{ctx}.effects.{e.get('id', e.get('type', '?'))}"
        if e.get("type") not in EFFECT_TYPES:
            err(f"{ectx}: неизвестный тип эффекта {e.get('type')} (есть: {', '.join(EFFECT_TYPES)})")
        if e.get("type") == "tint" and e.get("blend", "mul") not in BLENDS:
            err(f"{ectx}: blend {e.get('blend')} — допустимо {', '.join(BLENDS)}")
        if e.get("type") == "shapes":
            check_shapes(ectx + ".shapes", e.get("shapes", []))
        if e.get("type") == "rope":
            # G28: канат движка — from / to на экране, ширина [у ближнего конца, у дальнего]
            for k_ in ("from", "to"):
                v_ = e.get(k_)
                if not (isinstance(v_, list) and len(v_) == 2 and 0 <= v_[0] <= 1920 and 0 <= v_[1] <= 1080):
                    err(f"{ectx}: {k_} — точка [x, y] в кадре 1920×1080")
            w_ = e.get("width", [6, 3])
            if not (isinstance(w_, list) and 1 <= len(w_) <= 2 and all(0 < float(x) <= 40 for x in w_)):
                err(f"{ectx}: width [ближний, дальний] px, 0 < w ≤ 40")
        check_flags(ectx + ".if", e.get("if"))
        check_flags(ectx + ".unless", e.get("unless"))
    ph = room.get("background", {}).get("placeholder")
    if ph is not None:
        # Заглушка движка вместо заказанного арта (R2, R3): фигуры из данных, без кода комнаты на экране.
        if "image" in room.get("background", {}):
            err(f"{ctx}.background: и image, и placeholder — что-то одно")
        if not ph.get("shapes"):
            err(f"{ctx}.background.placeholder: нет shapes")
        check_shapes(ctx + ".background.placeholder.shapes", ph.get("shapes", []))
        if not str(room.get("_art", "")).strip():
            err(f"{ctx}: заглушка фона без _art — какой арт заказан и где (BRIEF_CHATGPT_*.md)")
    for l in room.get("layers", []):
        if "pivot" in l and (not isinstance(l["pivot"], list) or len(l["pivot"]) != 2):
            err(f"{ctx}.layers.{l.get('id', '?')}: pivot — [x, y] в пикселях слоя")
        if "spin" in l:
            if "pivot" not in l:
                err(f"{ctx}.layers.{l.get('id', '?')}: spin без pivot (вокруг чего вращать)")
            check_flags(f"{ctx}.layers.{l.get('id', '?')}.spin.if", l["spin"].get("if"))
            check_flags(f"{ctx}.layers.{l.get('id', '?')}.spin.unless", l["spin"].get("unless"))
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

    # 6б. зазор у мебели (Директор 18.10: «Агата чуть да проходит сквозь углы стола» в Z1): вырез — место ног,
    # а тело шире ног. clearance [{left/right — два края проекции предмета на пол (прямые), y [от, до],
    # half_width_px}]: каждая точка пола с y в диапазоне стоит левее левого края или правее правого
    # не меньше чем на half_width_px × масштаб глубины (сетка 4 px; то же на навигации Godot —
    # game/tests/test_room_geometry.gd).
    kind6 = room.get("background", {}).get("kind", "interior")
    dep6 = room.get("depth", index["defaults"].get("depth_exterior" if kind6 == "exterior" else "depth", {}))

    def scale6(y: float) -> float:
        span = dep6["bottom_y"] - dep6["top_y"]
        t = 1.0 if span == 0 else min(1.0, max(0.0, (y - dep6["top_y"]) / span))
        return dep6["scale_top"] + (dep6["scale_bottom"] - dep6["scale_top"]) * t

    def line_x(seg, y: float) -> float:
        (x1, y1), (x2, y2) = seg
        return x1 if y1 == y2 else x1 + (x2 - x1) * (y - y1) / (y2 - y1)

    for ci, cl in enumerate(room.get("clearance", [])):
        cctx = f"{ctx}.clearance[{ci}] ({cl.get('what', '?')})"
        if not all(k in cl for k in ("left", "right", "y", "half_width_px")):
            err(f"{cctx}: нужны left, right, y, half_width_px")
            continue
        y0, y1 = cl["y"]
        hw = float(cl["half_width_px"])
        bad = []
        for yy in range(int(y0) + 2, int(y1) - 1, 4):  # 2 px внутрь: точки НА границе выреза — пол
            sx = hw * scale6(yy)
            xl, xr = line_x(cl["left"], yy) - sx, line_x(cl["right"], yy) + sx
            for xx in range(int(xl) + 3, int(xr) - 1, 4):
                if walkable_point([xx, yy]):
                    bad.append((xx, yy))
        if bad:
            err(f"{cctx}: {len(bad)} точек пола ближе полуширины Агаты к краю — например {bad[0]}, {bad[-1]} "
                f"(тело Агаты войдёт в предмет; раздвиньте walkable_holes)")

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
        # предмет на выходе (ключ на дверь дома, Директор 18.10): применение должно открывать именно этот выход
        for it, act in (ex.get("item_use") or {}).items():
            ictx = f"{ctx}: выход в {to}.item_use[{it}]"
            check_items(ictx, [it])
            check_flags(ictx + ".sets", act.get("sets"))
            if act.get("once_flag"):
                check_flags(ictx + ".once_flag", [act["once_flag"]])
            if act.get("consumes") and it in items and not items[it].get("consumed"):
                err(f"{ictx}: расходует предмет, а в items.json consumed: false")
            need = set(edges[rid].get(to, []))
            if not need:
                err(f"{ictx}: выход открыт и без предмета — применение ничего не меняет")
            elif not need <= set(act.get("sets", [])):
                err(f"{ictx}: sets {act.get('sets')} не открывают выход (ребро требует {sorted(need)})")
        oc = ex.get("on_closed")
        if oc:
            check_flags(f"{ctx}.exit[{to}].on_closed", oc.get("sets"))
            if oc.get("spawn") and oc["spawn"] not in spawns:
                err(f"{ctx}: on_closed выхода в {to} ссылается на спавн {oc['spawn']}")
            if oc.get("scene") and oc["scene"] not in scenes:
                err(f"{ctx}: on_closed выхода в {to} ссылается на сцену {oc['scene']}")
    for to in edges.get(rid, {}):
        if to not in seen_targets:
            err(f"{ctx}: переход {rid}–{to} из locations.json не имеет выхода в комнате")

    # 9. подсказки выходов: метка или «нарисован в арте»; направление = край; метка кликабельна
    marks = []
    for ex in exits:
        to = ex.get("to")
        rect, _stand = exit_geometry(room, ex)
        if rect is None:
            continue
        cue = ex.get("cue")
        if cue is not None and cue not in CUE_KINDS:
            err(f"{ctx}: выход в {to}: cue '{cue}' — допустимо {', '.join(CUE_KINDS)}")
            continue
        d, at, src, edg = exit_cue(ex, rect)
        icon_problem = exit_icon_problem(ex)
        if icon_problem:
            err(f"{ctx}: выход в {to}: {icon_problem}")
        if src == "default":
            warn(f"{ctx}: выход в {to} внутри кадра без cue — считается нарисованной дверью; пометьте \"cue\": \"door\" (или направление, если это дорожка вглубь)")
        if d == "door":
            continue
        if edg and d not in edg and d != "up":
            err(f"{ctx}: выход в {to}: метка «{d}», а прямоугольник {rect} касается края {'/'.join(edg)} — направление метки должно совпадать с краем")
        if edg and d == "up":
            err(f"{ctx}: выход в {to}: метка «up» (вглубь) у прямоугольника на краю кадра {'/'.join(edg)}")
        x, y, w, h = rect
        hx, hy = (CUE_HALF_ACROSS, CUE_HALF_ALONG) if d in ("down", "up") else (CUE_HALF_ALONG, CUE_HALF_ACROSS)
        box = (at[0] - hx, at[1] - hy, at[0] + hx, at[1] + hy)
        if not (x <= at[0] <= x + w and y <= at[1] <= y + h):
            err(f"{ctx}: выход в {to}: метка {at} вне прямоугольника выхода {rect} — клик по метке не попадёт в выход")
        if box[1] < TOP_BAR + 6 or box[0] < 0 or box[2] > 1920 or box[3] > 1080:
            err(f"{ctx}: выход в {to}: метка {at} заходит под верхнюю панель или за кадр")
        for (oto, obox) in marks:
            if box[0] < obox[2] and obox[0] < box[2] and box[1] < obox[3] and obox[1] < box[3]:
                err(f"{ctx}: метки выходов в {oto} и {to} налезают друг на друга")
        marks.append((to, box))
        for prob in cue_path_problems(room, ex, rect, d, at, edg):
            err(f"{ctx}: выход в {to}: {prob}")
        notes.append(f"{rid}→{to}: метка {d}{' ' + str(ex['cue_deg']) + '°' if 'cue_deg' in ex else ''} ({src}) в ({at[0]:.0f}, {at[1]:.0f})")

    # хотспот под выходом недостижим кликом, если его pick_priority не выше приоритета выхода (1)
    def _overlap(a, b) -> bool:
        return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]

    def hs_rects(h: dict) -> list:
        """Базовый прямоугольник хотспота и прямоугольники его состояний (states[].rect)."""
        return [h["rect"]] + [s["rect"] for s in h.get("states", []) if "rect" in s]

    for h in room.get("hotspots", []):
        if "rect" not in h:
            continue
        for ex in exits:
            rect, _stand = exit_geometry(room, ex)
            if rect and any(_overlap(hr, rect) for hr in hs_rects(h)) and int(h.get("pick_priority", 0)) <= int(ex.get("pick_priority", 1)):
                err(f"{ctx}.{h.get('id')}: прямоугольник перекрывается выходом в {ex.get('to')} — клик уйдёт выходу (поднимите pick_priority или раздвиньте)")

    # и наоборот (дефект блока 3, 23.10: Тамара на улице O4 стояла на дороге к реке — клик по метке выхода «К реке»
    # уходил ей, тест прохождения не мог уйти с улицы): точка метки выхода (или центр его прямоугольника) не лежит
    # внутри хотспота NPC с приоритетом выше выхода — фигура заслонила бы выход от клика.
    for ex in exits:
        rect, _stand = exit_geometry(room, ex)
        if not rect:
            continue
        at_ = (ex.get("cue_at") or [rect[0] + rect[2] / 2, rect[1] + rect[3] / 2])
        for h in room.get("hotspots", []):
            if h.get("kind") != "npc" or "rect" not in h:
                continue
            if int(h.get("pick_priority", 0)) > int(ex.get("pick_priority", 1)) and any(
                    hr[0] <= at_[0] <= hr[0] + hr[2] and hr[1] <= at_[1] <= hr[1] + hr[3] for hr in hs_rects(h)):
                err(f"{ctx}.{h.get('id')}: фигура стоит на выходе в {ex.get('to')} (точка {at_}) — клик по выходу уйдёт ей")

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
            if any(_overlap(ra, rb) for ra in hs_rects(a) for rb in hs_rects(b)) and int(a.get("pick_priority", 0)) == int(b.get("pick_priority", 0)) and not _exclusive(a, b):
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
        for c in h.get("hidden_when", []):
            if not c.get("all"):
                err(f"{hctx}.hidden_when: условие без all — скрыло бы хотспот всегда")
            check_flags(hctx + ".hidden_when.all", c.get("all"))
            check_flags(hctx + ".hidden_when.not", c.get("not"))
        ph = h.get("placeholder")
        if ph is not None and ph.get("kind") != "silhouette":
            err(f"{hctx}.placeholder: kind {ph.get('kind')} — есть только silhouette")
        for st in h.get("states", []):
            check_flags(hctx + ".states", st.get("if"))
            if "stand" in st and not walkable_point(st["stand"]):
                err(f"{hctx}.states{st.get('if')}: stand {st['stand']} вне полигона (или в вырезе)")
            if "rect" in st and (len(st["rect"]) != 4 or st["rect"][2] <= 0 or st["rect"][3] <= 0):
                err(f"{hctx}.states{st.get('if')}: rect {st['rect']} — нужно [x, y, w, h] с w, h > 0")

        def check_action(actx: str, act: dict, scene_id: str | None) -> None:
            req = act.get("requires", {})
            check_flags(actx + ".requires", req.get("flags"))
            check_items(actx + ".requires", req.get("items"))
            check_flags(actx + ".sets", act.get("sets"))
            check_items(actx + ".gives", act.get("gives"))
            # restores: вернуть в сумку ранее выданный и оставленный предмет (варежка со ступени O2) — не новая выдача
            for it in act.get("restores", []) or []:
                check_items(actx + ".restores", [it])
                if it in items and not items[it].get("consumed"):
                    err(f"{actx}: restores {it} — предмет не расходуется (consumed: false), возвращать нечего")
                if it in items and not items[it].get("inventory"):
                    err(f"{actx}: restores {it} — не инвентарный предмет")
            ch_ = act.get("choice")
            if ch_:
                check_flags(actx + ".choice.requires", ch_.get("requires", {}).get("flags"))
                for o in ch_.get("options", []):
                    if "sets" not in o or "id" not in o:
                        err(f"{actx}.choice: вариант без id/sets")
                    check_flags(f"{actx}.choice.{o.get('id')}.requires", o.get("requires", {}).get("flags"))
                    check_items(f"{actx}.choice.{o.get('id')}.requires", o.get("requires", {}).get("items"))
                    if o.get("consumes_item"):
                        it_used = actx.rsplit("[", 1)[-1].rstrip("]") if "item_use[" in actx else ""
                        if it_used in items and not items[it_used].get("consumed"):
                            err(f"{actx}.choice.{o.get('id')}: расходует предмет {it_used}, а в items.json consumed: false")
            check_items(actx + ".consumes", act.get("consumes") if isinstance(act.get("consumes"), list) else None)
            if act.get("consumes") is True:
                it_used = actx.rsplit("[", 1)[-1].rstrip("]") if "item_use[" in actx else ""
                if it_used in items and not items[it_used].get("consumed"):
                    err(f"{actx}: расходует предмет {it_used}, а в items.json consumed: false")
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
                    src_hs = f"{rid}.{h.get('id')}"
                    if it in items and src_hs in [items[it].get("source_hotspot")] + list(items[it].get("source_hotspot_also", []) or []):
                        # предмет берут хотспотом без сцены (скоба в H2 — после плана из школы): только с requires
                        if not items[it].get("inventory", False):
                            err(f"{actx}: предмет {it} не инвентарный, его нельзя взять хотспотом")
                        # take_any_time: предмет нарочно берут когда угодно (язык колокола из коробки, Директор 23.10)
                        if not items[it].get("take_any_time") and not (act.get("requires") or {}).get("flags") and not (act.get("requires") or {}).get("items"):
                            warn(f"{actx}: {it} берётся без условий — тогда его выдаёт сцена (source_scene), а не хотспот")
                        if act.get("once_flag") != "has_" + it:
                            err(f"{actx}: взять {it} — once_flag должен быть has_{it} (второй раз не выдаётся)")
                    else:
                        err(f"{actx}: выдача предмета {it} без указания сцены (или items.json source_hotspot \"{src_hs}\")")

        if "use" in h:
            check_action(hctx + ".use", h["use"], h["use"].get("scene"))
        # use_when: действие по состоянию, когда use уже не готов (колокол с языком до зеркала конторы, 23.10);
        # synth_sound — звук движка (game/scripts/mechanics/synth_sfx.gd).
        for _i, _uw in enumerate(h.get("use_when", []) or []):
            if not isinstance(_uw, dict) or not (_uw.get("if") or _uw.get("unless")):
                err(f"{hctx}.use_when[{_i}]: нужен if или unless (иначе он всегда перекрывает осмотр)")
                continue
            check_action(f"{hctx}.use_when[{_i}]", _uw, _uw.get("scene"))
            if _uw.get("synth_sound") and _uw["synth_sound"] not in ("bell", "bell_long", "knock", "hammer", "shutter"):
                err(f"{hctx}.use_when[{_i}]: synth_sound «{_uw['synth_sound']}» — такого звука нет в SynthSfx")
        for it, act in (h.get("item_use") or {}).items():
            check_items(hctx + ".item_use", [it])
            check_action(f"{hctx}.item_use[{it}]", act, act.get("scene"))
        if "talk" in h:
            tk = h["talk"]
            if not isinstance(tk.get("scenes", []), list) or not all(isinstance(x, str) for x in tk.get("scenes", [])):
                err(f"{hctx}.talk.scenes: список id сцен по порядку разговора (дефект 22.10: сюда попал словарь scenes комнаты)")
                tk = dict(tk, scenes=[])
            for scn in ([tk["scene"]] if tk.get("scene") else []) + list(tk.get("scenes", [])):
                if scn not in scenes:
                    err(f"{hctx}.talk: неизвестная сцена {scn}")
                elif rid not in scenes[scn]["locations"]:
                    err(f"{hctx}.talk: сцена {scn} не идёт в {rid}")
            if tk.get("scene") and tk.get("scenes"):
                err(f"{hctx}.talk: и scene, и scenes — что-то одно")
            bt = tk.get("before_text")
            if isinstance(bt, dict):
                for k, v in bt.items():
                    if k != "default" and k not in tk.get("scenes", []):
                        err(f"{hctx}.talk.before_text: {k} — не сцена из talk.scenes")
                    check_text(f"{hctx}.talk.before_text.{k}", v)
            for e in tk.get("by_flags", []):
                check_flags(hctx + ".talk.by_flags.if", e.get("if"))
                check_text(hctx + ".talk.by_flags.text", e.get("text", ""))
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
                check_match_marks_mouse(hctx + ".puzzle", pz)
                check_winter_view(hctx + ".puzzle.art.winter_view", pz.get("art", {}))
        if "view" in h:
            check_view(hctx + ".view", h["view"])
            check_flags(hctx + ".view.unless", h["view"].get("unless"))
            check_flags(hctx + ".view.if", h["view"].get("if"))
            for i_, ph_ in enumerate(h["view"].get("photos", []) or []):
                check_res_path(f"{hctx}.view.photos[{i_}].image", ph_.get("image", ""))
                size_ = png_size(ph_.get("image", ""))
                r_ = ph_.get("region", [])
                if len(r_) != 4 or r_[2] <= 0 or r_[3] <= 0:
                    err(f"{hctx}.view.photos[{i_}].region: нужно [x, y, w, h]")
                elif size_ and (r_[0] < 0 or r_[1] < 0 or r_[0] + r_[2] > size_[0] or r_[1] + r_[3] > size_[1]):
                    err(f"{hctx}.view.photos[{i_}].region {r_} вне картинки {size_}")
            for i_, pi_ in enumerate(h["view"].get("pictures", []) or []):
                check_res_path(f"{hctx}.view.pictures[{i_}].image", pi_.get("image", ""))
                if len(pi_.get("rect", [])) != 4 or pi_["rect"][2] <= 0:
                    err(f"{hctx}.view.pictures[{i_}]: rect [x, y, w, h(0 — по пропорции)]")
            # 13б. лист с заказанной картинкой (pending, партия 9 — чистые развороты тетрадей G33, пустой лист письма G31):
            # пока файла нет, лист строится по stub (прежняя картинка с заплатками или лист движка — "image": null)
            all_papers_ = list(enumerate(h["view"].get("papers", []) or []))
            for pg_i, pg_ in enumerate(h["view"].get("pages", []) or []):
                all_papers_ += [(f"pages[{pg_i}].{j_}", pp_) for j_, pp_ in enumerate(pg_.get("papers", []) or [])]
            for i_, pa_ in all_papers_:
                if pa_.get("font") not in (None, "hand", "body", "body_italic", "body_bold", "head", "head_bold"):
                    err(f"{hctx}.view.papers[{i_}].font {pa_.get('font')} — нет такой роли (UiTheme.font)")
                if not pa_.get("pending"):
                    continue
                res_ = str(pa_.get("image", ""))
                st_ = pa_.get("stub")
                if (GAME_DIR / res_[len("res://"):]).exists() if res_.startswith("res://") else False:
                    warn(f"{hctx}.view.papers[{i_}]: {res_} уже в игре — pending/stub можно убрать")
                    continue
                req_ = MANIFEST_REQ.get(pa_["pending"])
                if req_ is None:
                    err(f"{hctx}.view.papers[{i_}]: pending {pa_['pending']} — нет такой заявки в assets/manifest.json")
                elif req_.get("status") not in PENDING_OPEN:
                    err(f"{hctx}.view.papers[{i_}]: файла {res_} нет, а заявка {pa_['pending']} — {req_.get('status')}: импортируйте арт")
                elif "incoming/" + Path(res_).name not in req_.get("files", []):
                    err(f"{hctx}.view.papers[{i_}]: incoming/{Path(res_).name} нет в заявке {pa_['pending']}")
                if not isinstance(st_, dict) or "image" not in st_:
                    err(f"{hctx}.view.papers[{i_}]: pending без stub.image (прежняя картинка или null — лист движка)")
                elif st_["image"] is not None:
                    check_res_path(f"{hctx}.view.papers[{i_}].stub.image", st_["image"])
            for i_, pa_ in enumerate(h["view"].get("papers", []) or []):
                r_ = list(pa_.get("rect", []))
                if "image" in pa_ and not (pa_.get("pending") and isinstance(pa_.get("stub"), dict)):
                    check_res_path(f"{hctx}.view.papers[{i_}].image", pa_["image"])
                    size_ = png_size(pa_["image"])
                    if len(r_) == 4 and r_[3] <= 0 and size_:
                        r_[3] = r_[2] * size_[1] / size_[0]
                    src_ = pa_.get("image_size") or size_
                    tr_ = pa_.get("text_rect")
                    if src_ and tr_ and (len(tr_) != 4 or tr_[0] < 0 or tr_[1] < 0 or tr_[0] + tr_[2] > src_[0] or tr_[1] + tr_[3] > src_[1]):
                        err(f"{hctx}.view.papers[{i_}].text_rect {tr_} вне листа {src_}")
                if len(r_) != 4 or r_[2] <= 0 or r_[3] <= 0:
                    err(f"{hctx}.view.papers[{i_}]: rect [x, y, w, h] (h 0 — только у листа-картинки)")
                elif r_[0] < 0 or r_[1] < 80 or r_[0] + r_[2] > 1920 or r_[1] + r_[3] > 1080:
                    err(f"{hctx}.view.papers[{i_}]: лист {r_} вне кадра или под верхней панелью")

        if "mechanic" in h:
            check_mechanic(hctx + ".mechanic", h["mechanic"], room)
        for it, act in (h.get("item_use") or {}).items():
            if act.get("open_mechanic") and "mechanic" not in h:
                err(f"{hctx}.item_use[{it}]: open_mechanic, а у хотспота нет mechanic")

    # текст при первом входе (on_enter): ключ текста и флаг «один раз» (иначе повторится после загрузки)
    for i_, oe in enumerate(room.get("on_enter", []) or []):
        if not oe.get("once_flag"):
            err(f"{ctx}.on_enter[{i_}]: без once_flag — текст повторится при каждом входе и после загрузки")
        else:
            check_flags(f"{ctx}.on_enter[{i_}].once_flag", [oe["once_flag"]])
        check_flags(f"{ctx}.on_enter[{i_}].if", oe.get("if"))

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
            # `or` [cond, …] — любое из условий (G15: два следа в классе или учительский ящик)
            stack = list(cw)
            while stack:
                cond = stack.pop()
                stack.extend(cond.get("or", []) or [])
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

# 10. предметы (Директор 18.10: «зачем нам брать предметы, которые нельзя применить»; аудит —
# Docs/ITEMS_AUDIT.md). consumed: true ⇔ предмет где-то расходуется (сцена consumes, item_use consumes у
# хотспота или выхода). Инвентарный предмет, который игрок получает в E0–E1, применяется в комнатах вехи
# (item_use хотспота или выхода, требование загадки) или объявляет later_use — сцены, где он нужен по
# сценарию (вне вехи), или no_use_reason — спорный случай, решение за Директором (предупреждение).
consumers: dict[str, list[str]] = {}
for sc in scenes.values():
    for it in sc.get("consumes", []) or []:
        consumers.setdefault(it, []).append(sc["id"])
appliers: dict[str, list[str]] = {}
for rid, room in rooms.items():
    for h in room.get("hotspots", []):
        for it, act in (h.get("item_use") or {}).items():
            if rid in in_scope:
                appliers.setdefault(it, []).append(f"{rid}.{h.get('id')}")
            if act.get("consumes") is True or any(o.get("consumes_item") for o in (act.get("choice") or {}).get("options", [])):
                consumers.setdefault(it, []).append(f"{rid}.{h.get('id')}")
        for it in h.get("puzzle", {}).get("requires", {}).get("items", []):
            if rid in in_scope:
                appliers.setdefault(it, []).append(f"{rid}.{h.get('id')} (загадка)")
    for ex in room.get("exits", []):
        for it, act in (ex.get("item_use") or {}).items():
            if rid in in_scope:
                appliers.setdefault(it, []).append(f"{rid}→{ex.get('to')}")
            if act.get("consumes") is True:
                consumers.setdefault(it, []).append(f"{rid}→{ex.get('to')}")
for it, meta in items.items():
    if meta.get("consumed") and it not in consumers:
        err(f"items.json: {it} consumed: true, но его нигде не расходуют (сцена consumes / item_use consumes)")
    if not meta.get("consumed") and it in consumers:
        err(f"items.json: {it} consumed: false, а его расходуют: {consumers[it]}")
scope_ids = {s["id"] for s in scope_scenes}
got_in_scope = set()
for s in scope_scenes:
    got_in_scope |= set(s.get("grants", {}).get("items", []))
for it, meta in items.items():   # предметы, которые берут хотспотом комнаты вехи (source_hotspot)
    if str(meta.get("source_hotspot", "")).partition(".")[0] in in_scope:
        got_in_scope.add(it)

# контрольные сохранения сцен (N01 → «День второй»): заголовок — ключ текста
for sc in scenes.values():
    cp = sc.get("checkpoint")
    if cp:
        check_text(f"сцена {sc['id']}.checkpoint.title", cp.get("title", ""))
for it in sorted(got_in_scope):
    meta = items.get(it, {})
    if not meta.get("inventory"):
        continue
    later = meta.get("later_use", [])
    for sid in later:
        if sid not in scenes:
            err(f"items.json: {it}.later_use — неизвестная сцена {sid}")
        elif sid in scope_ids:
            err(f"items.json: {it}.later_use {sid} — сцена этой вехи: применение должно быть в комнате (item_use)")
    if it in appliers:
        notes.append(f"предмет {it}: применяется в {', '.join(appliers[it])}" + (f"; дальше — {', '.join(later)}" if later else ""))
    elif later:
        notes.append(f"предмет {it}: в E0–E1 не применяется, по сценарию — {', '.join(later)}")
    elif meta.get("no_use_reason"):
        warn(f"предмет {it}: применения нет — {meta['no_use_reason']}")
    else:
        err(f"предмет {it} попадает в сумку в E0–E1, но нигде не применяется и не объявляет later_use / no_use_reason "
            f"(«не берём то, что нельзя применить», Docs/ITEMS_AUDIT.md)")

# ---------- блок 2 (22.10, Директор 23:53 «как поставить зеркало на стойку тети?»): куда идёт предмет ----------
# Предмет из сумки, который двигает сюжет (его item_use у хотспота или выхода комнаты вехи ведёт к сцене, открывает
# выход или ставит флаг, нужный сцене), на чужой цели отвечает не общим «Здесь это не пригодится», а подсказкой
# items.json wrong_target {text, rooms?} — и в комнате своей цели тоже. Для предметов дня второго цель журнала
# сцены, которая выдаёт предмет, называет комнату цели (слово названия места из locations.json).
_needed_flags: set[str] = set()
for _sc in scenes.values():
    _needed_flags |= set(_sc.get("requires", {}).get("flags", []))
_loc_names = {l["id"]: l.get("name", "") for l in locations.get("locations", [])}


def _progress_use(act: dict, is_exit: bool) -> bool:
    return is_exit or bool(act.get("scene")) or bool(set(act.get("sets", []) or []) & _needed_flags) or bool(act.get("open_mechanic"))


_targets: dict[str, set] = {}
_use_scenes: dict[str, set] = {}   # item -> scenes its use starts (their requires — the step before)
for rid in in_scope:
    room = rooms.get(rid, {})
    for h in room.get("hotspots", []):
        for it, act in (h.get("item_use") or {}).items():
            if isinstance(act, dict) and _progress_use(act, False) and items.get(it, {}).get("inventory"):
                _targets.setdefault(it, set()).add(rid)
                if act.get("scene"):
                    _use_scenes.setdefault(it, set()).add(str(act["scene"]))
    for ex in room.get("exits", []):
        for it, act in (ex.get("item_use") or {}).items():
            if isinstance(act, dict) and items.get(it, {}).get("inventory"):
                _targets.setdefault(it, set()).add(rid)
_day2 = {s_["id"] for f_ in ("E2.json", "E3.json") for s_ in load(STORY / "scenes" / f_)["scenes"]}
for it, trooms in sorted(_targets.items()):
    wt = items[it].get("wrong_target") or {}
    if not wt.get("text") or wt.get("text") == "@ui.item_no_effect":
        err(f"items.json: {it} двигает сюжет ({', '.join(sorted(trooms))}), но на чужой цели отвечает общим отказом — нужен wrong_target.text: куда этот предмет")
        continue
    check_text(f"items.json: {it}.wrong_target.text", wt["text"])
    wr = wt.get("rooms")
    if wr and not trooms <= set(wr):
        err(f"items.json: {it}.wrong_target.rooms {wr} не покрывает комнату цели {sorted(trooms - set(wr))}")
    # Цель журнала на шаге, когда предмет пора применить: сцена-источник или сцена перед той, что запускает применение.
    cands = [str(items[it].get("source_scene", ""))]
    for us in _use_scenes.get(it, set()):
        cands += [f[len("done_"):] for f in scenes.get(us, {}).get("requires", {}).get("flags", []) if f.startswith("done_")]
    cands = [c for c in cands if c in scenes]
    if not cands or not (set(cands) & _day2):
        continue   # предметы дня первого: цели журнала блока 1 приняты Директором как есть
    goals = " ".join(str(scenes[c].get("goal", "")) for c in cands).lower()
    for rid in trooms:
        words = [w.lower().strip("«»,.") for w in _loc_names.get(rid, "").split()]
        stems = [w[:-2] if len(w) > 5 else w for w in words if len(w) >= 4]
        if stems and not any(st in goals for st in stems):
            err(f"{'/'.join(cands)}: цель журнала не называет место, где применить {it} ({rid} «{_loc_names.get(rid, '')}»)")

# Выход с собственным `requires` (одно направление ребра: лодка с дальней опоры обратно — F13, 23.10): флаги известны,
# и у закрытого выхода есть closed_text — игрок слышит, почему нельзя.
for rid, room in sorted(rooms.items()):
    for ex in room.get("exits", []):
        if ex.get("requires"):
            for f in ex["requires"]:
                if f not in known_flags:
                    err(f"{rid}→{ex.get('to')}: requires {f} — нет в flags.json")
            if not ex.get("closed_text"):
                err(f"{rid}→{ex.get('to')}: выход с requires без closed_text")

# Предмет, который тратится внутри сцены (item_use … consumes, scene S), не входит в grants.items той же сцены:
# сцена завершается после траты, и её выдача вернула бы потраченное (язык колокола в M11 — ИИ-разбор логики 22.10, п. 7).
# Так же — предмет, который берут хотспотом (items.json source_hotspot), сцена не выдаёт вовсе (validate_story).
for rid, room in sorted(rooms.items()):
    for h in room.get("hotspots", []) + room.get("exits", []):
        for it, act in (h.get("item_use") or {}).items():
            if not isinstance(act, dict) or not act.get("consumes"):
                continue
            sc_id = str(act.get("scene", ""))
            if sc_id and it in (scenes.get(sc_id, {}).get("grants", {}).get("items", []) or []):
                err(f"{rid}.{h.get('id', h.get('to'))}.item_use.{it}: предмет тратится в сцене {sc_id}, а её grants.items его выдают — после завершения он вернулся бы в сумку")

# Кадр (frame: true) называет своё место в строке комнаты: place — id локации или title — ключ текста (23.10: над классом
# и ужином эпилога стояло «Береговой поворот» — имя комнаты под кадром).
for rid, room in sorted(rooms.items()):
    if not room.get("frame"):
        continue
    if "place" in room:
        if room["place"] not in loc_ids:
            err(f"{rid}: place {room['place']} — нет такой локации")
    elif "title" in room:
        t = str(room["title"])
        if not t.startswith("@") or t[1:] not in texts:
            err(f"{rid}: title {t} — нет такого текста")
    else:
        err(f"{rid}: кадр без place / title — в строке комнаты останется имя комнаты под ним")

# Флаг, от которого зависит видимость в комнате (visible_if / hidden_if / if / unless / if_any), кто-то должен ставить:
# сцена (grants, sets постановки, выбор реплики), задание, хотспот (sets, once_flag, выбор), вход в комнату. Флаг,
# только объявленный в комнате, — мёртвое условие (дефект 23.10: жена Ильи в O3 по wife_came, а его никто не ставил).
_AUTO_FLAG = re.compile(r"^(done_|started_|has_|visited_|seen_room_|tod_)")   # tod_ — время суток, выводится из истории
_set_anywhere: set[str] = set()


def _collect_sets(o) -> None:
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ("sets", "flags", "also") and isinstance(v, (list, str)):
                _set_anywhere.update([v] if isinstance(v, str) else [x for x in v if isinstance(x, str)])
            elif k == "once_flag" and isinstance(v, str):
                _set_anywhere.add(v)
            _collect_sets(v)
    elif isinstance(o, list):
        for x in o:
            _collect_sets(x)


_collect_sets(list(scenes.values()))
_collect_sets(list(rooms.values()))
_collect_sets(load(STORY / "start_points.json") if (STORY / "start_points.json").exists() else {})


def _used_conditions(o, out: set) -> None:
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ("visible_if", "hidden_if", "if", "unless", "if_any") and isinstance(v, list):
                out.update(x for x in v if isinstance(x, str))
            _used_conditions(v, out)
    elif isinstance(o, list):
        for x in o:
            _used_conditions(x, out)


for rid, room in sorted(rooms.items()):
    _used: set[str] = set()
    _used_conditions(room.get("hotspots", []) + room.get("exits", []) + room.get("layers", []) + room.get("effects", []), _used)
    for fl in sorted(_used):
        if not _AUTO_FLAG.match(fl) and fl not in _set_anywhere:
            err(f"{rid}: условие по флагу {fl} — его никто не ставит (ни сцена, ни задание, ни хотспот, ни вход в комнату)")

# G41 (Директор 23.10: Тамара «стоит и на перекрёстке, и на почте»): один персонаж — одно место. Сюжет проходится по
# порядку основных сцен так же, как точки старта (RoomManager.start_at): у каждой сцены два состояния — начата
# (started_) и завершена (done_ + grants + флаги complete_when её комнат); необязательные истории — «идёт» (все флаги
# условий с её префиксом, q02_…) и «завершена» (+ done_ и grants) с момента, когда выполнены её requires. В каждом
# состоянии хотспот-NPC с одним id виден (visible_if / hidden_if / hidden_when) не больше чем в одной комнате. Кадры
# (frame: true) не в счёт — это постановка, не место.
def _npc_visible(h: dict, fl: set) -> bool:
    if any(f not in fl for f in h.get("visible_if", [])):
        return False
    if any(f in fl for f in h.get("hidden_if", [])):
        return False
    for c in h.get("hidden_when", []):
        if all(f in fl for f in c.get("all", [])) and not any(f in fl for f in c.get("not", [])):
            return False
    return True


def check_one_place() -> None:
    npcs: dict[str, list] = {}
    cond: set[str] = set()
    for rid, room in rooms.items():
        if room.get("frame"):
            continue
        for h in room.get("hotspots", []):
            if h.get("kind") == "npc":
                npcs.setdefault(h["id"], []).append((rid, h))
                cond |= set(h.get("visible_if", [])) | set(h.get("hidden_if", []))
                for c in h.get("hidden_when", []):
                    cond |= set(c.get("all", [])) | set(c.get("not", []))
    fl: set[str] = set()
    states: list[tuple[str, set]] = []
    for sid, sc in scenes.items():
        if sc.get("type") != "main":
            continue
        fl.add("started_" + sid)
        states.append(("started_" + sid, set(fl)))
        fl.add("done_" + sid)
        fl |= set((sc.get("grants") or {}).get("flags", []))
        for rid, room in rooms.items():
            cw = (room.get("scenes") or {}).get(sid, {}).get("complete_when", [])
            for c in (cw if isinstance(cw, list) else [cw]):
                fl |= set(c.get("all", []))
                if c.get("any"):
                    fl.add(c["any"][0])
        states.append(("done_" + sid, set(fl)))
    extra: list[tuple[str, set]] = []
    for q in quests:
        if q.get("reserve"):
            continue
        qid = q["id"]
        pre = qid.lower() + "_"
        own = {f for f in cond if f.startswith(pre)}
        need = set((q.get("requires") or {}).get("flags", []))
        for name, s in states:
            if need <= s:
                extra.append((f"{name} + {qid} идёт", s | own | {"started_" + qid}))
                extra.append((f"{name} + {qid} завершена", s | own | {"started_" + qid, "done_" + qid} | set(scenes[qid]["grants"]["flags"])))
                break
    seen: set[tuple] = set()
    for name, s in states + extra:
        for cid, places in sorted(npcs.items()):
            where = sorted(rid for rid, h in places if _npc_visible(h, s))
            if len(where) > 1 and (cid, tuple(where)) not in seen:
                seen.add((cid, tuple(where)))
                err(f"{cid}: виден сразу в {', '.join(where)} (состояние {name}) — один персонаж стоит в одном месте (G41): "
                    f"разведите visible_if / hidden_if / hidden_when по сюжету")


check_one_place()

_cue_selfcheck()

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
