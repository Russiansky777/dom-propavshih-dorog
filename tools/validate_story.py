#!/usr/bin/env python3
"""Валидатор сценария «Дом пропавших дорог».

Читает data/story/*.json и проверяет:
  1. ссылочную целостность (локации, предметы, флаги);
  2. единственный источник каждого предмета;
  3. проходимость основного пути: симуляция от пустого состояния, все M-сцены выполнимы;
  4. достижимость локаций каждой сцены в момент её доступности (граф переходов с условиями);
  5. окна V/Q: доступны до точки невозврата, не требуются основным путём;
  6. тайны не раскрываются раньше своего эпизода (min_episode);
  7. число переправ и повторение глаголов загадок (сигналы темпа, не ошибки);
  8. постановка сцен (stage: затемнение, перенос в комнату, звуки) и контрольные сохранения (checkpoint):
     at — номер реплики или "end", комната — из locations сцены, звуки — из sfx.json, слот — не ручной;
  1г–1е. текст: цели и подсказки не называют факт раньше его флага (KNOWLEDGE_GATES), закадровый голос сцен не
     говорит «мама» вне кавычек, в JSON сюжета нет повторяющихся ключей (ИИ-чтение непрерывности 23.10);
  1ж. одно имя тёти: «Евдокия» — только в первом объяснении (M01, Тамара), дальше «Дуня» (H1, Директор 24.10).
  1з. подсказки к старым словам: каждое [[слово|значение]] — в data/story/glossary.json (форма и значение), без «висящих» [[ ]] (H59, T7).
Предмет, который игрок берёт сам в комнате (items.json source_hotspot «<комната>.<хотспот>»: хотспот с use.gives и
use.requires), — единственный источник вместо выдачи сцены; симуляция даёт его, как только requires выполнены и
комната достижима (скоба для плиты в мастерской — после плана из школы, блок 1 22.10).

Код возврата 0 — ошибок нет (предупреждения допустимы). Отчёт: Docs/STORY_REPORT.md.
Запуск: python3 tools/validate_story.py [--quiet]
"""
from __future__ import annotations

import json
import re
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
line_choice_flags: set[str] = set()
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
    # выбор внутри разговора (M13: ответ Павлу) — mandatory_lines[].options[].sets; это тоже флаги выбора
    for ln in s.get("mandatory_lines", []):
        for opt in ln.get("options", []):
            if "sets" in opt:
                granted_flags.setdefault(opt["sets"], []).append(s["id"])
                line_choice_flags.add(opt["sets"])
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

# Флаги первого входа в комнату (rooms/<LOC>.json → on_enter[].once_flag с условиями if): C12 (23.10) — боковую
# дверь галереи Агата открывает изнутри при первом входе в галерею (house_open). Симуляция ставит флаг, как только
# комната достижима и условия if выполнены (unless — не мешает: в симуляции флаги только прибавляются).
for rf in sorted((STORY / "rooms").glob("*.json")):
    if rf.name.startswith("_"):
        continue
    room_doc = json.loads(rf.read_text(encoding="utf-8"))
    for oe in room_doc.get("on_enter", []) or []:
        once = str(oe.get("once_flag", ""))
        if not once or room_doc["id"] not in loc_ids:
            continue
        ul = {"loc": room_doc["id"], "item": "", "sets": [once], "req": list(oe.get("if", []) or [])}
        room_unlocks.append(ul)
        granted_flags.setdefault(once, []).append(f"{ul['loc']}:вход")

# Предметы, которые игрок берёт сам хотспотом комнаты (items.json → source_hotspot «<комната>.<хотспот>»):
# use.gives с use.requires. Не выдача сцены: симуляция даёт предмет, как только requires выполнены и комната
# достижима; сцена такой предмет выдавать не должна (единственный источник).
room_takes: list[dict] = []
for it_id, it_meta in item_by_id.items():
    src = it_meta.get("source_hotspot")
    if not src:
        continue
    # source_hotspot_also: тот же предмет на другом месте той же комнаты (скоба H2 на табурете, пока на её месте
    # стоит зеркало конторы, блок 2) — хотспот существует и выдаёт этот предмет, once_flag тот же (has_<id>).
    for also in it_meta.get("source_hotspot_also", []) or []:
        arid, _, ahid = str(also).partition(".")
        arf = STORY / "rooms" / f"{arid}.json"
        ahs = None
        if arf.exists():
            ahs = next((h for h in json.loads(arf.read_text(encoding="utf-8")).get("hotspots", []) if h.get("id") == ahid), None)
        if arid != str(src).partition(".")[0] or ahs is None:
            err(f"предмет {it_id}: source_hotspot_also {also} — нет такого хотспота в комнате {str(src).partition('.')[0]}")
        elif it_id not in ((ahs.get("use") or {}).get("gives") or []) or (ahs.get("use") or {}).get("once_flag") != "has_" + it_id:
            err(f"предмет {it_id}: source_hotspot_also {also} — должен выдавать его с once_flag has_{it_id}")
    rid_, _, hid_ = str(src).partition(".")
    rf_ = STORY / "rooms" / f"{rid_}.json"
    if not rf_.exists():
        err(f"предмет {it_id}: source_hotspot {src} — нет комнаты {rid_}")
        continue
    room_doc = json.loads(rf_.read_text(encoding="utf-8"))
    hs_ = next((h for h in room_doc.get("hotspots", []) if h.get("id") == hid_), None)
    if hs_ is None:
        err(f"предмет {it_id}: source_hotspot {src} — нет хотспота {hid_} в {rid_}")
        continue
    use_ = hs_.get("use") or {}
    if it_id not in (use_.get("gives") or []):
        err(f"предмет {it_id}: хотспот {src} его не выдаёт (use.gives)")
        continue
    if it_meta.get("source_location") not in (None, rid_):
        err(f"предмет {it_id}: source_location {it_meta.get('source_location')} ≠ комната хотспота {rid_}")
    room_takes.append({"loc": rid_, "item": it_id, "req": list((use_.get("requires") or {}).get("flags", [])),
                       "req_items": list((use_.get("requires") or {}).get("items", []))})

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
    if fl not in declared_flags and not fl.startswith(auto_prefixes) and fl not in line_choice_flags:
        # флаги выборов тоже допускаем без описания
        if not any(fl in [o.get("sets") for ch in by_id.get(sid, {}).get("choices", []) for o in ch["options"]] for sid in srcs) \
                and not all(str(sid).endswith(":вход") for sid in srcs):   # флаг входа объявлен в своей комнате (rooms/*.json → flags)
            warn(f"флаг {fl} выдаётся ({', '.join(srcs)}), но не описан в flags.json")

# ---------- 1б. цели журнала для игрока (goal) без служебных кодов ----------
# Игра показывает goal (или result, если goal нет). Коды комнат/эпизодов/сцен игроку не показываем
# (решение 17.10: «Цели журнала и любой текст для игрока не содержат кодов»). Для сыгранных эпизодов goal обязателен.
import re as _re
# «ЗМ» в кавычках-ёлочках — надпись на тётиной стойке, которую видит игрок (Директор 23:53: цель называет место), а не код.
_code = _re.compile(r"(?<!«)\b(" + "|".join(sorted(loc_ids, key=len, reverse=True)) + r"|E[0-7]|[MVQ]\d\d|ЗМ|ЗГ|ЗП)\b(?!»)")
_played = {"M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "N01"}
for s in scenes:
    if s.get("type") != "main":
        continue
    g = s.get("goal")
    if g is not None and _code.search(g):
        err(f"{s['id']}: цель журнала (goal) содержит служебный код «{_code.search(g).group(0)}»")
    if g is None and s["id"] in _played:
        err(f"{s['id']}: у сыгранной сцены нет goal — игроку покажется заметка сценария (result)")

# ---------- 1в. подсказки: у каждой основной сцены дней 1–2 (D1, ИИ-плейтест 22.10) ----------
# Игрок, который не знает следующего шага, жмёт «Подсказка» — она берёт hints сцены, что ждёт следующей. Без них —
# общие слова, и в классе O1 игрок 40 шагов ходил по кругу. Каждая основная сцена эпизодов 0–3 — не меньше двух ступеней.
for sc_h in scenes:
    ep_h = sc_h.get("_episode", sc_h.get("episode", -1))
    if sc_h.get("type") == "main" and str(ep_h) in ("0", "1", "2", "3"):
        if len(sc_h.get("hints") or []) < 2:
            err(f"{sc_h['id']}: у основной сцены дней 1–2 нет подсказок (hints, хотя бы две ступени)")

# ---------- 1г. цели и подсказки не называют факт раньше, чем игрок его узнал (ИИ-чтение 23.10: C6, C7, C10) ----------
# Цель журнала (goal) видна после своей сцены, подсказки (hints) — пока сцена ждёт. Факт из таблицы можно назвать, только
# если его флаг к этому моменту гарантирован: выдан самой сценой (только для goal) или сценами, которых она требует
# (done_<id> в requires, по цепочке). Сцены свободного порядка (M23a–M23d) друг другу ничего не гарантируют.
# Таблица: шаблон (без учёта регистра) → флаги (хватит одного) → откуда игрок узнаёт факт.
KNOWLEDGE_GATES = [
    (r"перв\w*\s+бревн\w*", {"bridge_decided"}, "о мосте решают на мельнице (M23b)"),
    (r"управляющ\w*\s+(?:\w+\s+)?вернул\w*|вернул\w*\s+(?:\w+\s+)?управляющ\w*", {"manager_returned"},
     "управляющего Агата видит во дворе мельницы (M23b)"),
    (r"завал\w*", {"knows_sluice_key", "met_pavel"}, "завал конторы — от Пелагеи (необязательный вопрос) или от Павла (M09)"),
]
_guar_cache: dict[str, set[str]] = {}


def guaranteed_before(sid: str) -> set[str]:
    """Флаги, которые точно стоят, когда сцена sid доступна: её requires и всё, что выдают требуемые сцены."""
    if sid in _guar_cache:
        return _guar_cache[sid]
    out = set(by_id[sid]["requires"].get("flags", []))
    for fl in list(out):
        prev = fl[len("done_"):] if fl.startswith("done_") else ""
        if prev in by_id:
            out |= guaranteed_before(prev) | set(by_id[prev]["grants"].get("flags", []))
    _guar_cache[sid] = out
    return out


for s in mains:
    before = guaranteed_before(s["id"])
    after = before | set(s["grants"].get("flags", []))
    shown = [("цель журнала", s.get("goal") or "", after)]
    shown += [(f"подсказка {i + 1}", h, before) for i, h in enumerate(s.get("hints") or [])]
    for where, text, known in shown:
        for pat, need, why in KNOWLEDGE_GATES:
            m = _re.search(pat, text, _re.IGNORECASE)
            if m and not (need & known):
                err(f"{s['id']}: {where} называет «{m.group(0)}» раньше, чем игрок это узнал ({why}; "
                    f"нужен один из флагов {', '.join(sorted(need))}): «{text}»")

# ---------- 1д. закадровый голос сцен — в третьем лице: не «мама» вне кавычек (ИИ-чтение 23.10: V12) ----------
# «Мама» — слово Агаты. Рассказчик сцен называет Нину по имени; цитата надписи или письма в «ёлочках» — можно.
_quoted = _re.compile(r"«[^»]*»")
for s in scenes:
    lines_n = s.get("mandatory_lines") or s.get("lines") or []
    for i, ln in enumerate(lines_n):
        if ln.get("speaker") != "narrator":
            continue
        bare = _quoted.sub("", str(ln.get("text", "")))
        m = _re.search(r"\bмам\w*", bare, _re.IGNORECASE)
        if m:
            err(f"{s['id']}.{i}: закадровый голос говорит «{m.group(0)}» — рассказчик называет Нину по имени: «{ln.get('text')}»")

# ---------- 1е. повторяющиеся ключи в JSON сюжета (flags.json: waved_at_stove дважды, 23.10) ----------
# Парсер молча берёт последнее значение — правка первого не видна в игре.
def _dup_hook(pairs):
    seen: set[str] = set()
    for k, _v in pairs:
        if k in seen:
            _dups.append(k)
        seen.add(k)
    return dict(pairs)


for _jf in sorted(STORY.rglob("*.json")):
    _dups: list[str] = []
    json.loads(_jf.read_text(encoding="utf-8"), object_pairs_hook=_dup_hook)
    if _dups:
        err(f"{_jf.relative_to(ROOT)}: ключ повторяется в одном объекте — {', '.join(sorted(set(_dups)))}")

# ---------- 1ж. одно имя тёти — «Дуня» (H1, Директор 24.10, 00:19) ----------
# «Евдокия» — только в одном первом объяснении (M01, Тамара: «тёти Дуни, маминой сестры. Евдокией её только в
# бумагах звали»); дальше везде, включая заметки, — «Дуня». Латиница в id флагов (knows_evdokia_death) не в счёт.
AUNT_FULL_NAME_ALLOWED = "scenes/E0.json:M01.mandatory_lines"


def _aunt_hits(o, path: str, out: list[str]) -> None:
    if isinstance(o, dict):
        for k, v in o.items():
            _aunt_hits(v, f"{path}.{k}", out)
    elif isinstance(o, list):
        for i, v in enumerate(o):
            _aunt_hits(v, f"{path}[{i}]", out)
    elif isinstance(o, str) and "Евдоки" in o:
        out.append(path)


_aunt_found: list[str] = []
for _jf in sorted(STORY.rglob("*.json")):
    _doc = json.loads(_jf.read_text(encoding="utf-8"))
    _rel = str(_jf.relative_to(STORY))
    if _rel == "scenes/E0.json":
        for _s in _doc.get("scenes", []):
            _aunt_hits(_s, f"{_rel}:{_s.get('id')}", _aunt_found)
    else:
        _aunt_hits(_doc, _rel, _aunt_found)
_aunt_bad = [p for p in _aunt_found if not p.startswith(AUNT_FULL_NAME_ALLOWED)]
if _aunt_bad:
    err(f"H1: «Евдокия» вне первого объяснения ({AUNT_FULL_NAME_ALLOWED}) — дальше только «Дуня»: {', '.join(_aunt_bad[:8])}")
if len(_aunt_found) - len(_aunt_bad) != 1:
    err(f"H1: первое объяснение «тётя Дуня — Евдокия, мамина сестра» должно быть ровно одно (в {AUNT_FULL_NAME_ALLOWED}), найдено {len(_aunt_found) - len(_aunt_bad)}")

# ---------- 1и. снятое решениями Директора — нигде, кроме заметок ----------
# Р4 (29.10): стеллажа в конторе нет — дверь перекосило паводком, засов изнутри сам упал в скобы (стр. 86: «в тексте его
# двигают, а в игре его нигде нет»). Ключи «_…» — заметки разработки, в игру не идут.
GONE_WORDS = {"стеллаж": "Р4 (29.10): стеллажа в конторе нет"}


def _gone_walk(o, path: str, out: list[tuple[str, str]]) -> None:
    if isinstance(o, dict):
        for k, v in o.items():
            if not str(k).startswith("_"):
                _gone_walk(v, f"{path}.{k}", out)
    elif isinstance(o, list):
        for i, v in enumerate(o):
            _gone_walk(v, f"{path}[{i}]", out)
    elif isinstance(o, str):
        low = o.lower()
        for w in GONE_WORDS:
            if w in low:
                out.append((path, w))


_gone: list[tuple[str, str]] = []
for _jf in sorted(STORY.rglob("*.json")):
    _gone_walk(json.loads(_jf.read_text(encoding="utf-8")), str(_jf.relative_to(STORY)), _gone)
for _p, _w in _gone[:12]:
    err(f"{_p}: «{_w}» — {GONE_WORDS[_w]}")

# ---------- 1з. подсказки к старым словам [[слово|значение]] (H59, T7, Директор 24.10) ----------
# Каждое помеченное слово — в data/story/glossary.json (та же форма и то же значение, есть источник со ссылкой);
# «висящих» [[ / ]] и пустых частей нет; в строке не больше одной подсказки; в каждой словарной статье слово встречается.
GLOSS_RE = re.compile(r"\[\[([^\[\]|]+)\|([^\[\]|]+)\]\]")
_gloss_doc = json.loads((STORY / "glossary.json").read_text(encoding="utf-8")) if (STORY / "glossary.json").is_file() else None
if _gloss_doc is None:
    err("H59: нет data/story/glossary.json — словарь подсказок к старым словам")
_gloss = {}
for _g in (_gloss_doc or {}).get("words", []):
    _w = str(_g.get("word", ""))
    if not _w or not str(_g.get("meaning", "")).strip() or not str(_g.get("lemma", "")).strip():
        err(f"glossary.json: у статьи «{_w}» нет слова, леммы или значения")
    if not str((_g.get("source") or {}).get("url", "")).startswith("http"):
        err(f"glossary.json: у статьи «{_w}» нет ссылки на словарь (source.url)")
    if _w.lower() in _gloss:
        err(f"glossary.json: статья «{_w}» повторяется")
    _gloss[_w.lower()] = _g
_gloss_used: set[str] = set()


def _gloss_walk(o, path: str) -> None:
    if isinstance(o, dict):
        for k, v in o.items():
            _gloss_walk(v, f"{path}.{k}")
    elif isinstance(o, list):
        for i, v in enumerate(o):
            _gloss_walk(v, f"{path}[{i}]")
    elif isinstance(o, str) and ("[[" in o or "]]" in o or "|" in o and "[" in o):
        marks = GLOSS_RE.findall(o)
        rest = GLOSS_RE.sub("", o)
        if "[[" in rest or "]]" in rest:
            err(f"H59: {path}: «висящая» разметка подсказки (нужно [[слово|значение]]): «{o[:80]}»")
        if len(marks) > 1:
            err(f"H59: {path}: больше одной подсказки в строке")
        for w, m in marks:
            g = _gloss.get(w.lower())
            if g is None:
                err(f"H59: {path}: слова «{w}» нет в data/story/glossary.json")
                continue
            _gloss_used.add(w.lower())
            if m.strip() != str(g.get("meaning", "")).strip():
                err(f"H59: {path}: значение «{m}» у «{w}» ≠ glossary.json («{g.get('meaning')}»)")


for _jf in sorted(STORY.rglob("*.json")):
    if _jf.name == "glossary.json" or _jf.relative_to(STORY).parts[0] in ("ambient", "time"):
        continue   # описания схем слоёв с [[x,y]] — не тексты игрока
    _gloss_walk(json.loads(_jf.read_text(encoding="utf-8")), str(_jf.relative_to(STORY)))
for _w in sorted(set(_gloss) - _gloss_used):
    warn(f"glossary.json: слово «{_gloss[_w].get('word')}» нигде не помечено в тексте")

# ---------- 2. единственный источник предметов ----------
item_sources: dict[str, list[str]] = {}
for s in scenes:
    for it in s["grants"].get("items", []):
        item_sources.setdefault(it, []).append(s["id"])
for it, meta_it in item_by_id.items():
    srcs = item_sources.get(it, [])
    if meta_it.get("source_hotspot"):
        if srcs:
            err(f"предмет {it}: берётся хотспотом {meta_it['source_hotspot']}, а его ещё и выдаёт сцена {srcs} — два источника")
        continue
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
        if ui in applied_unlocks or (ul["item"] and ("has_" + ul["item"]) not in flags) or not set(ul["req"]) <= flags:
            continue
        if shortest(cur_loc, ul["loc"], flags) is None:
            continue
        flags |= set(ul["sets"])
        applied_unlocks.add(ui)
        unlock_log.append(f"{ul['loc']}: {ul['item'] or 'первый вход'} → {', '.join(ul['sets'])} (перед {len(order) + 1}-й основной сценой)")
    for ti, tk in enumerate(room_takes):
        if ("take", ti) in applied_unlocks or not set(tk["req"]) <= flags \
                or not all(("has_" + x) in flags for x in tk["req_items"]):
            continue
        if shortest(cur_loc, tk["loc"], flags) is None:
            continue
        flags.add("has_" + tk["item"])
        applied_unlocks.add(("take", ti))
        unlock_log.append(f"{tk['loc']}: взять {tk['item']} (перед {len(order) + 1}-й основной сценой)")
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

# ---------- 8. постановка сцен и контрольные сохранения ----------
frame_rooms = set()
for rf_ in sorted((STORY / "rooms").glob("*.json")):
    if not rf_.name.startswith("_") and json.loads(rf_.read_text(encoding="utf-8")).get("frame"):
        frame_rooms.add(rf_.stem)
SCENE_MECHANICS = ("windlass", "crossing")
_switches = meta.get("switches", {}) or {}
_room_local_flags: set[str] = set()
for rf_ in sorted((STORY / "rooms").glob("*.json")):
    if not rf_.name.startswith("_"):
        _room_local_flags |= set((json.loads(rf_.read_text(encoding="utf-8")).get("flags") or {}).keys())


_TOD_INDEX = STORY / "time" / "_index.json"
_TOD: set[str] = set()
if _TOD_INDEX.exists():   # время суток (F17): виртуальные флаги tod_<состояние|фаза>, tod_day<N>, tod_dark
    _TOD.add("tod_dark")
    for _s in json.loads(_TOD_INDEX.read_text(encoding="utf-8")).get("states", []):
        for _n in (_s.get("id"), _s.get("phase"), f"day{_s.get('day', 0)}"):
            if _n:
                _TOD.add("tod_" + str(_n))


def check_conditions(ctx: str, o: dict) -> None:
    """Условия реплики или постановки: флаги if / unless / if_any известны; switch — переключатель meta.json."""
    for k in ("if", "unless", "if_any"):
        for fl in o.get(k, []) or []:
            if fl not in granted_flags and fl not in declared_flags and fl not in _room_local_flags and fl not in _TOD \
                    and not fl.startswith(("done_", "has_", "q0", "q1", "v0", "board_", "pavel_answer_", "tikhon_told_", "beam_")):
                err(f"{ctx}: условие {k} — неизвестный флаг {fl}")
    sw = o.get("switch")
    if sw:
        name = sw.replace("!=", "=").split("=", 1)[0]
        if name not in _switches:
            err(f"{ctx}: switch {sw!r} — нет переключателя {name} в meta.json → switches")


# ---------- 1и. цель журнала по флагам (goal_left, T8: свободный день называет только несделанное) ----------
# Каждый пункт — с условием (if / unless — известные флаги), иначе он «сделанным» никогда не пропадёт; тексты без кодов.
for s in scenes:
    gl = s.get("goal_left")
    if gl is None:
        continue
    gctx = f"{s['id']}.goal_left"
    if not isinstance(gl, dict) or not gl.get("items") or not gl.get("none"):
        err(f"{gctx}: нужны items (что ещё не сделано) и none (если сделано всё)")
        continue
    for k in ("lead", "head", "none"):
        if gl.get(k) and _code.search(str(gl[k])):
            err(f"{gctx}.{k}: служебный код «{_code.search(str(gl[k])).group(0)}»")
    for j, it in enumerate(gl["items"]):
        if not (it.get("if") or it.get("unless")):
            err(f"{gctx}.items[{j}]: нет условия — пункт не пропадёт, когда сделан")
        if _code.search(str(it.get("text", ""))):
            err(f"{gctx}.items[{j}]: служебный код в тексте")
        check_conditions(f"{gctx}.items[{j}]", it)


_sfx_doc = load("sfx.json") if (STORY / "sfx.json").exists() else {}
_sfx_ids = set((_sfx_doc.get("sounds") or {}).keys())
# J (стр. 145, 169): «synth:<имя>» — звук, который делает движок (SynthSfx), имена — ветки match в synth_sfx.gd
_synth_src = (ROOT / "game" / "scripts" / "mechanics" / "synth_sfx.gd")
_synth_ids = set(re.findall(r'^\t\t"([a-z_]+)":', _synth_src.read_text(encoding="utf-8"), re.M)) if _synth_src.exists() else set()
for s in scenes:
    lines_n = len(s.get("mandatory_lines", []))
    for i, st in enumerate(s.get("stage", []) or []):
        sctx = f"{s['id']}.stage[{i}]"
        at = st.get("at")
        if not (at == "end" or (isinstance(at, int) and 0 <= at < max(lines_n, 1))):
            err(f"{sctx}: at {at!r} — номер реплики 0..{lines_n - 1} или \"end\"")
        for k in ("fade_out_s", "hold_s", "fade_in_s"):
            v = st.get(k, 0)
            if not isinstance(v, (int, float)) or v < 0 or v > 10:
                err(f"{sctx}: {k} {v!r} — секунды 0..10")
        dim = st.get("dim", 0.0)
        if not isinstance(dim, (int, float)) or not 0 <= dim < 1:
            err(f"{sctx}: dim {dim!r} — 0 ≤ dim < 1 (полумрак поверх комнаты, реплики видны)")
        if "room" in st:
            if st["room"] not in s["locations"]:
                err(f"{sctx}: комната {st['room']} не из locations сцены {s['locations']}")
            room_f = STORY / "rooms" / f"{st['room']}.json"
            spawns_ = json.loads(room_f.read_text(encoding="utf-8")).get("spawns", {}) if room_f.exists() else {}
            if st.get("spawn", "default") not in spawns_:
                err(f"{sctx}: в комнате {st['room']} нет спавна {st.get('spawn', 'default')}")
        for snd in st.get("sounds", []) or []:
            sid_ = str(snd.get("id", ""))
            if sid_.startswith("synth:"):
                if _synth_ids and sid_[6:] not in _synth_ids:
                    err(f"{sctx}: звука движка {sid_} нет в SynthSfx")
            elif _sfx_ids and snd.get("id") not in _sfx_ids:
                err(f"{sctx}: звука {snd.get('id')} нет в sfx.json (новых звуков не заводим)")
        # блоки 3–4: кадр поверх мира (FrameView) — комната-картина с "frame": true; "" — убрать кадр
        if "frame" in st and st["frame"] != "":
            if st["frame"] not in frame_rooms:
                err(f"{sctx}: кадр {st['frame']} — нет data/story/rooms/{st['frame']}.json с \"frame\": true")
        for fl in st.get("sets", []) or []:
            if fl not in granted_flags and fl not in declared_flags:
                err(f"{sctx}: sets {fl} — флаг нигде не описан и не выдаётся")
        check_conditions(sctx, st)
    # условия реплик (if / unless / if_any / switch): флаги известны, переключатель есть в meta.json
    for i, ln in enumerate(s.get("mandatory_lines", [])):
        check_conditions(f"{s['id']}.mandatory_lines[{i}]", ln)
        # строки-продолжения (then): показываются сразу после этой, каждая по своим условиям; не сдвигают нумерацию
        # записанных голосов <scene>_<index> (StoryRunner, line_id <scene>_<index>_then<k>)
        then_ = ln.get("then", [])
        if not isinstance(then_, list):
            err(f"{s['id']}.mandatory_lines[{i}].then — список строк")
            then_ = []
        for k, t in enumerate(then_):
            tctx = f"{s['id']}.mandatory_lines[{i}].then[{k}]"
            if not str(t.get("text", "")).strip() or "options" in t or "then" in t:
                err(f"{tctx}: нужна строка text (без options и вложенных then)")
            check_conditions(tctx, t)
    # крупный план посреди сцены (mechanics: окно ворота M25): номер реплики, флаг «сделано», тип
    for i, mc in enumerate(s.get("mechanics", []) or []):
        mctx = f"{s['id']}.mechanics[{i}]"
        at = mc.get("at")
        if not (at == "end" or (isinstance(at, int) and 0 <= at < max(lines_n, 1))):
            err(f"{mctx}: at {at!r} — номер реплики 0..{lines_n - 1} или \"end\" (после всех реплик)")
        until = mc.get("until", "")
        sets_ = [f for ev in (mc.get("spec", {}).get("events") or {}).values() for f in ev.get("sets", [])]
        if not until or until not in sets_:
            err(f"{mctx}: until {until!r} должен ставиться событием крупного плана (spec.events.*.sets)")
        if mc.get("spec", {}).get("type") not in SCENE_MECHANICS:
            err(f"{mctx}: тип {mc.get('spec', {}).get('type')!r} — есть {', '.join(SCENE_MECHANICS)}")
    ef = s.get("end_frame")
    if ef is not None:
        for e_ in ([{"frame": ef}] if isinstance(ef, str) else ef):
            if e_.get("frame") not in frame_rooms:
                err(f"{s['id']}.end_frame: {e_.get('frame')} — не кадр (rooms/*.json с \"frame\": true)")
    cp = s.get("checkpoint")
    if cp:
        if not cp.get("slot") or cp["slot"] in ("auto", "quick", "1", "2", "3", "pre_finale"):
            err(f"{s['id']}.checkpoint: слот {cp.get('slot')!r} — свой, не авто/быстрый/ручной")
        if not str(cp.get("title", "")).startswith("@"):
            err(f"{s['id']}.checkpoint: title — ключ текста @…")

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
# Число сцен по сценарию: 35 — день первый с «Ночью у печи» N01 (блок 1, 22.10); день 2 переписан по
# Docs/SCENARIO_FINAL.md (блок 2: E2 — 9 основных, утро — в конце N01; E3 — 8; прежние V04, V05 сняты вместе с эхом и
# наградой Павла) — 41/10/10. Блоки 3–4 (22.10): E4 — 10 основных (M19–M23d), E5 — 3 (M24 — вечер третьего дня после
# слияния совета с мельницей по D21, M25, M26); прежние E6/E7 и V06–V12 сняты вместе со старой цепью — 38/3/10.
# Полировка 22.10 (A1): M16s «Белый берег» — тот берег белый по узлу, до огней — 39/3/10.
# T6 (24.10): N02 «Ночь в Ольховке» — день второй кончается сном у мамы — 40/3/10.
# J (Директор 29.10, Р10): нижняя улица убрана вместе с Q09 «Ольховая улица» — 40/3/9.
expected = {"main": 40, "minor": 3, "quest": 9}
for k, v in expected.items():
    if counts[k] != v:
        err(f"сцен типа {k}: {counts[k]}, ожидалось {v}")

proposed = [(s["id"], s["proposed_change"]) for s in scenes if s.get("proposed_change")]

# Переименованный флаг (meta.json flag_renames, Р4 29.10: office_shelf_lifted → office_door_opened): новое имя объявлено,
# старого нет ни во flags.json, ни в данных — иначе старые сохранения и новые данные разойдутся.
_story_text = "\n".join(p_.read_text(encoding="utf-8") for p_ in STORY.rglob("*.json") if p_.name != "meta.json")
for _old, _new in (meta.get("flag_renames") or {}).items():
    if _old.startswith("_"):
        continue
    if _new not in declared_flags:
        err(f"meta.json flag_renames: {_old} → {_new}: нового флага нет во flags.json")
    if _old in declared_flags or f'"{_old}"' in _story_text:
        err(f"meta.json flag_renames: старое имя {_old} ещё в данных — заменить на {_new}")


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
