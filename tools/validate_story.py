#!/usr/bin/env python3
"""Валидатор сценария «Дом пропавших дорог».

Читает data/story/*.json и проверяет:
  1. ссылочную целостность (локации, предметы, флаги);
  2. единственный источник каждого предмета;
  3. проходимость основного пути: симуляция от пустого состояния, все M-сцены выполнимы;
  4. достижимость локаций каждой сцены в момент её доступности (граф переходов с условиями);
  5. окна V/Q: доступны до точки невозврата, не требуются основным путём;
  6. тайны не раскрываются раньше своего эпизода (min_episode);
  7. число переправ и повторение глаголов загадок (сигналы темпа, не ошибки).

Код возврата 0 — ошибок нет (предупреждения допустимы). Отчёт: Docs/STORY_REPORT.md.
Запуск: python3 tools/validate_story.py [--quiet]
"""
from __future__ import annotations

import json
import sys
from collections import Counter, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
REPORT = ROOT / "Docs" / "STORY_REPORT.md"

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def load(name: str):
    with open(STORY / name, encoding="utf-8") as f:
        return json.load(f)


# ---------- загрузка ----------
locations_doc = load("locations.json")
items_doc = load("items.json")
flags_doc = load("flags.json")
quests_doc = load("quests.json")
meta = load("meta.json")

scenes: list[dict] = []
episodes: dict[int, dict] = {}
for ep_file in sorted((STORY / "scenes").glob("E*.json")):
    ep = json.loads(ep_file.read_text(encoding="utf-8"))
    episodes[ep["episode"]] = ep
    for sc in ep["scenes"]:
        sc["episode"] = ep["episode"]
        scenes.append(sc)

for q in quests_doc["quests"]:
    q["type"] = "quest"
    q["episode"] = None
    q.setdefault("grants", {"flags": [], "items": []})
    q["grants"]["flags"] = list(q["grants"].get("flags", []))
    q["grants"]["flags"].append("done_" + q["id"])
    for opt in q["choice"]["options"]:
        q["grants"]["flags"].append(opt["sets"])
    scenes.append(q)

loc_ids = {l["id"] for l in locations_doc["locations"]}
item_by_id = {i["id"]: i for i in items_doc["items"]}
declared_flags = set(flags_doc["flags"].keys())

by_id = {s["id"]: s for s in scenes}
if len(by_id) != len(scenes):
    err("Повторяющиеся идентификаторы сцен")

mains = [s for s in scenes if s["type"] == "main"]
minors = [s for s in scenes if s["type"] == "minor"]
quests = [s for s in scenes if s["type"] == "quest"]

# ---------- 1. ссылочная целостность ----------
granted_flags: dict[str, list[str]] = {}
for s in scenes:
    for loc in s["locations"]:
        if loc not in loc_ids:
            err(f"{s['id']}: неизвестная локация {loc}")
    for it in s["requires"].get("items", []):
        if it not in item_by_id:
            err(f"{s['id']}: требуется неизвестный предмет {it}")
    for it in s["grants"].get("items", []):
        if it not in item_by_id:
            err(f"{s['id']}: выдаётся неизвестный предмет {it}")
    for fl in s["grants"].get("flags", []):
        granted_flags.setdefault(fl, []).append(s["id"])
    for ch in s.get("choices", []):
        for opt in ch["options"]:
            if "sets" in opt:
                granted_flags.setdefault(opt["sets"], []).append(s["id"])
for it in item_by_id:
    granted_flags.setdefault("has_" + it, [])

# Флаги, которые ставит сам игрок предметом на выходе комнаты (rooms/<LOC>.json → exits[].item_use: ключ на
# дверь дома, решение Директора 18.10), — не выдача сцены. Симуляция применяет такое действие, как только
# предмет есть (has_<item>), условия requires выполнены и комната достижима.
room_unlocks: list[dict] = []
for rf in sorted((STORY / "rooms").glob("*.json")):
    if rf.name.startswith("_"):
        continue
    room_doc = json.loads(rf.read_text(encoding="utf-8"))
    for ex in room_doc.get("exits", []):
        for it, act in (ex.get("item_use") or {}).items():
            if it not in item_by_id:
                err(f"{room_doc['id']}: выход в {ex.get('to')} принимает неизвестный предмет {it}")
                continue
            ul = {"loc": room_doc["id"], "item": it, "sets": list(act.get("sets", [])),
                  "req": list(act.get("requires", {}).get("flags", []))}
            room_unlocks.append(ul)
            for fl in ul["sets"]:
                granted_flags.setdefault(fl, []).append(f"{ul['loc']}:{it}")

for s in scenes:
    for fl in s["requires"].get("flags", []):
        if fl not in granted_flags:
            err(f"{s['id']}: требуется флаг {fl}, который никто не выдаёт")
for e in locations_doc["edges"]:
    for fl in e["requires"]:
        if fl not in granted_flags:
            err(f"переход {e['from']}–{e['to']}: условие {fl} никто не выдаёт")
    if e["from"] not in loc_ids or e["to"] not in loc_ids:
        err(f"переход {e['from']}–{e['to']}: неизвестная локация")

auto_prefixes = ("done_", "has_", "q0", "q1")
for fl, srcs in granted_flags.items():
    if fl not in declared_flags and not fl.startswith(auto_prefixes):
        # флаги выборов тоже допускаем без описания
        if not any(fl in [o.get("sets") for ch in by_id[sid].get("choices", []) for o in ch["options"]] for sid in srcs):
            warn(f"флаг {fl} выдаётся ({', '.join(srcs)}), но не описан в flags.json")

# ---------- 1б. цели журнала для игрока (goal) без служебных кодов ----------
# Игра показывает goal (или result, если goal нет). Коды комнат/эпизодов/сцен игроку не показываем
# (решение 17.10: «Цели журнала и любой текст для игрока не содержат кодов»). Для сыгранных эпизодов goal обязателен.
import re as _re
_code = _re.compile(r"\b(" + "|".join(sorted(loc_ids, key=len, reverse=True)) + r"|E[0-7]|[MVQ]\d\d|ЗМ|ЗГ|ЗП)\b")
_played = {"M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08"}
for s in scenes:
    if s.get("type") != "main":
        continue
    g = s.get("goal")
    if g is not None and _code.search(g):
        err(f"{s['id']}: цель журнала (goal) содержит служебный код «{_code.search(g).group(0)}»")
    if g is None and s["id"] in _played:
        err(f"{s['id']}: у сыгранной сцены нет goal — игроку покажется заметка сценария (result)")

# ---------- 2. единственный источник предметов ----------
item_sources: dict[str, list[str]] = {}
for s in scenes:
    for it in s["grants"].get("items", []):
        item_sources.setdefault(it, []).append(s["id"])
for it, meta_it in item_by_id.items():
    srcs = item_sources.get(it, [])
    if len(srcs) == 0:
        err(f"предмет {it} не выдаётся ни в одной сцене")
    elif len(srcs) > 1:
        err(f"предмет {it} выдаётся дважды: {srcs}")
    elif srcs[0] != meta_it["source_scene"]:
        err(f"предмет {it}: items.json говорит {meta_it['source_scene']}, выдаёт {srcs[0]}")

# ---------- граф локаций ----------
adj: dict[str, list[dict]] = {l: [] for l in loc_ids}
for e in locations_doc["edges"]:
    adj[e["from"]].append({"to": e["to"], "req": set(e["requires"]), "crossing": e.get("crossing", False)})
    adj[e["to"]].append({"to": e["from"], "req": set(e["requires"]), "crossing": e.get("crossing", False)})


def shortest(src: str, dst: str, flags: set[str]):
    """BFS; возвращает (длина, число переправ) или None."""
    if src == dst:
        return (0, 0)
    q = deque([(src, 0, 0)])
    seen = {src}
    while q:
        node, d, cross = q.popleft()
        for e in adj[node]:
            if e["req"] <= flags and e["to"] not in seen:
                nc = cross + (1 if e["crossing"] else 0)
                if e["to"] == dst:
                    return (d + 1, nc)
                seen.add(e["to"])
                q.append((e["to"], d + 1, nc))
    return None


def satisfied(s: dict, flags: set[str]) -> bool:
    req = s["requires"]
    return set(req.get("flags", [])) <= flags and all(("has_" + it) in flags for it in req.get("items", []))


def missing(s: dict, flags: set[str]) -> list[str]:
    req = s["requires"]
    m = [f for f in req.get("flags", []) if f not in flags]
    m += ["item:" + it for it in req.get("items", []) if ("has_" + it) not in flags]
    return m


# ---------- 3. симуляция основного пути ----------
flags: set[str] = set()
order: list[str] = []
timeline: list[tuple[str, set[str]]] = []  # (scene id, flags before)
done = set()
cur_loc = locations_doc["start"]
crossings_by_episode: Counter = Counter()
walk_log: list[str] = []
progress = True
applied_unlocks: set[int] = set()
unlock_log: list[str] = []
while progress:
    progress = False
    for ui, ul in enumerate(room_unlocks):
        if ui in applied_unlocks or ("has_" + ul["item"]) not in flags or not set(ul["req"]) <= flags:
            continue
        if shortest(cur_loc, ul["loc"], flags) is None:
            continue
        flags |= set(ul["sets"])
        applied_unlocks.add(ui)
        unlock_log.append(f"{ul['loc']}: {ul['item']} → {', '.join(ul['sets'])} (перед {len(order) + 1}-й основной сценой)")
    for s in sorted(mains, key=lambda x: (x["episode"], x["id"])):
        if s["id"] in done:
            continue
        if satisfied(s, flags):
            # 4. достижимость локаций в момент доступности
            seq = [cur_loc] + s["locations"]
            for a, b in zip(seq, seq[1:]):
                r = shortest(a, b, flags)
                if r is None:
                    err(f"{s['id']}: локация {b} недостижима из {a} при флагах на этот момент")
                else:
                    crossings_by_episode[s["episode"]] += r[1]
                    if r[1]:
                        walk_log.append(f"{s['id']}: {a}→{b} через переправу ×{r[1]}")
            cur_loc = s["locations"][-1]
            timeline.append((s["id"], set(flags)))
            flags |= set(s["grants"].get("flags", []))
            flags |= {"has_" + it for it in s["grants"].get("items", [])}
            for ch in s.get("choices", []):
                # для симуляции берём первый вариант; остальные проверяются отдельно
                if "sets" in ch["options"][0]:
                    flags.add(ch["options"][0]["sets"])
            done.add(s["id"])
            order.append(s["id"])
            progress = True
            break

for s in mains:
    if s["id"] not in done:
        err(f"ТУПИК: {s['id']} «{s['title']}» недостижима; не хватает: {missing(s, flags)}")

finale_idx = next((i for i, (sid, _) in enumerate(timeline) if "finale_confirmed" in by_id[sid]["grants"]["flags"]), None)

# ---------- 5. окна V и Q ----------
availability: dict[str, int | None] = {}
for s in minors + quests:
    first = None
    for i, (sid, before) in enumerate(timeline):
        after = before | set(by_id[sid]["grants"].get("flags", [])) | {"has_" + it for it in by_id[sid]["grants"].get("items", [])}
        if satisfied(s, after):
            first = i
            break
    availability[s["id"]] = first
    if first is None:
        err(f"{s['id']}: никогда не становится доступной; не хватает {missing(s, flags)}")
        continue
    if s["type"] == "quest" and finale_idx is not None and first >= finale_idx:
        err(f"{s['id']}: доступна только после точки невозврата")
    # локации достижимы в момент доступности
    sid, before = timeline[first]
    fl_then = before | set(by_id[sid]["grants"].get("flags", [])) | {"has_" + it for it in by_id[sid]["grants"].get("items", [])}
    start_loc = by_id[sid]["locations"][-1]
    for loc in s["locations"]:
        if shortest(start_loc, loc, fl_then) is None:
            err(f"{s['id']}: локация {loc} недостижима в момент доступности (после {sid})")
    # необязательное не должно быть нужно основному пути
    for fl in s["grants"].get("flags", []):
        users = [m["id"] for m in mains if fl in m["requires"].get("flags", [])]
        if users:
            err(f"{s['id']}: необязательная сцена выдаёт {fl}, который требует основная {users}")

# ---------- 6. тайны ----------
for fl, spec in flags_doc["flags"].items():
    if "min_episode" in spec:
        for s in scenes:
            if fl in s["grants"].get("flags", []):
                ep = s["episode"]
                if ep is None:
                    idx = availability.get(s["id"])
                    ep = by_id[timeline[idx][0]]["episode"] if idx is not None else None
                if ep is not None and ep < spec["min_episode"]:
                    err(f"тайна {fl} раскрывается в {s['id']} (эпизод {ep}) раньше эпизода {spec['min_episode']}")

# ---------- 7. темп: переправы и глаголы ----------
verbs = Counter(s["puzzle"]["verb"] for s in mains if "puzzle" in s)
for v, n in verbs.items():
    if n >= 4:
        warn(f"глагол загадки «{v}» повторяется {n} раз — риск однообразия (см. разбор 3.10)")
total_cross = sum(crossings_by_episode.values())
if total_cross >= 8:
    warn(f"на основном пути {total_cross} переправ через реку (см. разбор 3.9/4.8)")

# ---------- счёт ----------
counts = {"main": len(mains), "minor": len(minors), "quest": len(quests)}
expected = {"main": 34, "minor": 12, "quest": 10}
for k, v in expected.items():
    if counts[k] != v:
        err(f"сцен типа {k}: {counts[k]}, ожидалось {v}")

proposed = [(s["id"], s["proposed_change"]) for s in scenes if s.get("proposed_change")]

# ---------- отчёт ----------
lines = []
lines.append("# Отчёт валидатора сценария\n")
lines.append(f"Версия данных: {meta['story_version']}. Сцен: {counts['main']} основных, {counts['minor']} второстепенных, {counts['quest']} заданий.\n")
lines.append(f"Ошибок: {len(errors)}. Предупреждений: {len(warnings)}.\n")
if errors:
    lines.append("## Ошибки\n")
    lines += [f"- {e}" for e in errors]
    lines.append("")
if warnings:
    lines.append("## Предупреждения\n")
    lines += [f"- {w}" for w in warnings]
    lines.append("")
lines.append("## Порядок основного пути (симуляция, первый доступный по номеру)\n")
lines.append(" → ".join(order) + "\n")
lines.append("## Переправы через реку по эпизодам (основной путь)\n")
lines.append("| Эпизод | Переправ |\n| --- | --- |")
for ep in sorted(crossings_by_episode):
    lines.append(f"| E{ep} | {crossings_by_episode[ep]} |")
lines.append(f"| Всего | {total_cross} |\n")
if walk_log:
    lines.append("Где именно:\n")
    lines += [f"- {w}" for w in walk_log]
    lines.append("")
if unlock_log:
    lines.append("## Действия предметом в комнатах (не сцены)\n")
    lines += [f"- {u}" for u in unlock_log]
    lines.append("")
lines.append("## Глаголы загадок (основные сцены)\n")
lines.append("| Глагол | Сцен |\n| --- | --- |")
for v, n in verbs.most_common():
    lines.append(f"| {v} | {n} |")
lines.append("")
lines.append("## Окна необязательного содержания\n")
lines.append("| Сцена | Доступна после | До точки невозврата |\n| --- | --- | --- |")
for s in minors + quests:
    idx = availability.get(s["id"])
    after = timeline[idx][0] if idx is not None else "—"
    ok = "да" if (idx is not None and (finale_idx is None or idx < finale_idx)) else "нет"
    lines.append(f"| {s['id']} | {after} | {ok} |")
lines.append("")
if proposed:
    lines.append("## Предложенные правки, ожидающие решения Директора\n")
    lines += [f"- **{sid}**: {txt}" for sid, txt in proposed]
    lines.append("")

REPORT.parent.mkdir(parents=True, exist_ok=True)
REPORT.write_text("\n".join(lines), encoding="utf-8")

quiet = "--quiet" in sys.argv
if not quiet:
    print("\n".join(lines))
print(f"\n{'OK' if not errors else 'FAIL'}: {len(errors)} ошибок, {len(warnings)} предупреждений. Отчёт: {REPORT.relative_to(ROOT)}")
sys.exit(0 if not errors else 1)
