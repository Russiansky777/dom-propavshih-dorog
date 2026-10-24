#!/usr/bin/env python3
"""Выгрузка всех видимых игроку текстов в один TSV (UTF-8) для правки (H59, T3).

    python3 -I tools/export_texts.py [--out Docs/text_export/ru_all.tsv]

Колонки: id, speaker, scene_room, context, text. Обратный импорт — tools/import_texts.py
(тот же файл + колонка new_text). Табуляция, перевод строки и обратная косая черта в полях
экранируются обратимо: \\t, \\n, \\r, \\\\.

Что выгружается (то, что игра показывает; см. game/scripts/core/story_data.gd, story_runner.gd):
  text:<ключ>            data/story/text/*.json → texts.<ключ>.text (осмотры, подписи, мысли, реакции, UI)
  text:<ключ>#line       … → texts.<ключ>.line.text (та же запись — репликой персонажа)
  scene:<id>/…           data/story/scenes/*.json → mandatory_lines (text, voice_text, prompt, context,
                         options[].label/text, then[].text), goal (только main — цель журнала), hints[]
  quest:<id>/…           data/story/quests.json → lines[].text / voice_text, hints[]
  item:<id>/name         items.json → name (название в сумке)
  char:<id>/name         characters.json → name (имя говорящего над репликой)
  loc:<id>/name          locations.json → name (подпись комнаты, слоты сохранений)
  flag:<id>/desc         flags.json → desc (журнал: «Что известно»)
  ui_code:<файл>:<хеш>   русские строки, зашитые в game/scripts/ui/*.gd (импорт их не пишет)

Не выгружается (служебное, игрок не видит): поля с «_» в начале ключа, title/premise/summary/result/
actions/puzzle/logic сцен (сценарные заметки; title сцены идёт в context), steps/title/if_skipped/choice
квестов, items.use, characters.role/voice, locations.contents/edges.how/zones, флаги в rooms/*.json
(объявления для валидатора), start_points/music/meta/ambient (служебные подписи и отладочный оверлей).
Строки, начинающиеся с «@», — ссылки на text/*.json, они выгружаются там.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
UI_CODE = ROOT / "game" / "scripts" / "ui"
DEFAULT_OUT = ROOT / "Docs" / "text_export" / "ru_all.tsv"
COLUMNS = ["id", "speaker", "scene_room", "context", "text"]
CYR = re.compile("[А-Яа-яЁё]")


# --- TSV escaping (shared with import_texts.py) -------------------------------------------------

def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")


def unesc(s: str) -> str:
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            d = s[i + 1]
            m = {"\\": "\\", "t": "\t", "n": "\n", "r": "\r"}.get(d)
            if m is not None:
                out.append(m)
                i += 2
                continue
        out.append(c)
        i += 1
    return "".join(out)


# --- Rows -----------------------------------------------------------------------------------------

class Row:
    __slots__ = ("id", "speaker", "scene_room", "context", "text", "file", "path", "importable")

    def __init__(self, id_, speaker, scene_room, context, text, file, path, importable=True):
        self.id = id_
        self.speaker = speaker
        self.scene_room = scene_room
        self.context = context
        self.text = text
        self.file = file          # Path relative to ROOT (str)
        self.path = tuple(path)   # JSON path: str keys / int indices
        self.importable = importable


def _load(rel: str):
    with open(STORY / rel, encoding="utf-8") as f:
        return json.load(f)


def _is_ref(s) -> bool:
    return isinstance(s, str) and s.startswith("@")


def _cond(d: dict) -> str:
    parts = []
    for k in ("if", "if_any", "unless", "switch"):
        if k in d and d[k] not in (None, "", []):
            v = d[k]
            parts.append("%s: %s" % (k, ", ".join(map(str, v)) if isinstance(v, list) else v))
    return (" · " + "; ".join(parts)) if parts else ""


class Collector:
    def __init__(self):
        self.rows: list[Row] = []
        self.locations = {}
        self.char_names = {}
        self.texts = {}           # key -> entry
        self.text_file = {}       # key -> rel file
        self.voice = {}
        self.refs = {}            # "@key" -> first referencing place (short)
        self.items = {}

    # ---- helpers
    def add(self, *a, **kw):
        self.rows.append(Row(*a, **kw))

    def loc_name(self, lid: str) -> str:
        return self.locations.get(lid, {}).get("name", "")

    def room_label(self, rid: str) -> str:
        n = self.loc_name(rid)
        return f"{rid} {n}".strip()

    def text_of(self, key: str) -> str:
        e = self.texts.get(key)
        return e.get("text", "") if isinstance(e, dict) else ""

    # ---- references "@key" → where they are used (for context)
    def _scan_refs(self):
        def walk(o, where, path):
            if isinstance(o, dict):
                for k, v in o.items():
                    if not str(k).startswith("_"):
                        walk(v, where, path + [str(k)])
            elif isinstance(o, list):
                for i, v in enumerate(o):
                    tag = str(i)
                    if isinstance(v, dict):
                        for idk in ("id", "to", "slot"):
                            if isinstance(v.get(idk), str):
                                tag = v[idk]
                                break
                    walk(v, where, path + [tag])
            elif _is_ref(o):
                self.refs.setdefault(o[1:], f"{where}: {'.'.join(path)}")
        for p in sorted((STORY / "rooms").glob("*.json")):
            walk(_load(f"rooms/{p.name}"), f"rooms/{p.stem}", [])
        for p in sorted((STORY / "scenes").glob("*.json")):
            walk(_load(f"scenes/{p.name}"), f"scenes/{p.stem}", [])
        for rel in ("items.json", "quests.json", "menu.json", "achievements.json", "map_zarechye.json"):
            if (STORY / rel).exists():
                walk(_load(rel), rel[:-5], [])
        for p in sorted((STORY / "time").glob("*.json")):
            walk(_load(f"time/{p.name}"), f"time/{p.stem}", [])

    # ---- text/*.json
    FIELD_DESC = [
        ("label", "подпись при наведении"),
        ("label_*", "подпись при наведении (другое состояние)"),
        ("look*", "осмотр"),
        ("use*", "действие с объектом"),
        ("closed*", "закрытый выход: почему не пройти"),
        ("opt_*", "вариант выбора (кнопка)"),
        ("prompt", "вопрос выбора"),
        ("react_*", "реакция после выбора"),
        ("title", "заголовок крупного плана"),
        ("title_*", "заголовок листа крупного плана"),
        ("paper_*", "текст листа крупного плана"),
        ("written_*", "надпись мелом/карандашом"),
        ("after*", "повторный разговор"),
        ("before*", "до разговора"),
        ("thought", "мысль"),
        ("take", "взять в сумку"),
        ("done", "после выбора"),
        ("wrong", "предмет здесь не подходит"),
        ("again", "повторный осмотр"),
    ]

    def _field_desc(self, field: str) -> str:
        for pat, d in self.FIELD_DESC:
            if fnmatch.fnmatchcase(field, pat):
                return f"{d} ({field})"
        return field

    def _text_speaker(self, key: str) -> str:
        parts = key.split(".")
        section, field = parts[0], parts[-1]
        nar = self.voice.get("narration", {})
        for ch, spec in nar.get("by_speaker", {}).items():
            if isinstance(spec, dict) and key in spec.get("keys", []):
                return ch
        if section in ("ui", "map", "ach"):
            return "ui"
        if len(parts) >= 3 or section in ("item",):
            for pat in ("title_*", "paper_*", "written_*"):
                if fnmatch.fnmatchcase(field, pat):
                    return "written"
            for pat in nar.get("skip_fields", []):
                if fnmatch.fnmatchcase(field, pat):
                    return "ui"
        if key in nar.get("skip_keys", []):
            return "ui"
        return "narrator"

    def _text_place(self, key: str) -> tuple[str, str]:
        """(scene_room, context prefix) for a text key."""
        parts = key.split(".")
        section = parts[0]
        if section == "ui":
            return "UI", "интерфейс"
        if section == "map":
            return "UI", "план Заречья"
        if section == "ach":
            return "UI", "финальный экран «Что осталось» · след выбора"
        if section == "item":
            iid = parts[1]
            nm = self.items.get(iid, {}).get("name", iid)
            if len(parts) > 2:
                return "сумка", f"предмет «{nm}» · {self._field_desc(parts[-1])}"
            return "сумка", f"предмет «{nm}» · строка при получении/наведении в сумке"
        if section == "examine":
            iid = parts[1]
            nm = self.items.get(iid, {}).get("name", iid)
            rest = (" · " + self._field_desc(parts[-1])) if len(parts) > 2 else ""
            return "сумка", f"рассмотреть предмет «{nm}»{rest}"
        if section == "mech":
            obj = parts[1] if len(parts) > 2 else ""
            return "крупный план", f"механика {obj} · {self._field_desc(parts[-1])}"
        m = re.match(r"^([A-Z]+\d*)([a-z]*)$", section)
        rid = m.group(1) if m else section
        variant = {"d": " (день 2+)", "q": " (квест)"}.get(m.group(2), "") if m and m.group(2) else ""
        sr = self.room_label(rid) if self.loc_name(rid) else section
        if len(parts) < 3:
            return sr, self._field_desc(parts[-1]) + variant
        obj, field = parts[1], parts[-1]
        if obj.startswith("exit_"):
            to = obj[5:]
            objd = f"выход → {self.room_label(to)}"
        else:
            lbl = self.text_of(f"{section}.{obj}.label") or self.text_of(f"{rid}.{obj}.label")
            objd = f"«{lbl}» ({obj})" if lbl else obj
        mid = (" · " + ".".join(parts[2:-1])) if len(parts) > 3 else ""
        return sr, f"{objd}{mid} · {self._field_desc(field)}{variant}"

    def collect_texts(self):
        for p in sorted((STORY / "text").glob("*.json")):
            if p.name.startswith("_"):
                continue
            rel = f"text/{p.name}"
            doc = _load(rel)
            for key, entry in doc.get("texts", {}).items():
                if not isinstance(entry, dict):
                    continue
                self.texts[key] = entry
                self.text_file.setdefault(key, rel)
        for p in sorted((STORY / "text").glob("*.json")):
            if p.name.startswith("_"):
                continue
            rel = f"text/{p.name}"
            doc = _load(rel)
            fpath = f"data/story/{rel}"
            for key, entry in doc.get("texts", {}).items():
                if not isinstance(entry, dict):
                    continue
                sr, ctx = self._text_place(key)
                ref = self.refs.get(key)
                ref_s = f" · где: {ref}" if ref else ""
                t = entry.get("text")
                if isinstance(t, str):
                    line = entry.get("line")
                    extra = " · запасной закадровый вариант (звучит line)" if isinstance(line, dict) and line.get("text") else ""
                    self.add(f"text:{key}", self._text_speaker(key), sr, ctx + extra + ref_s, t,
                             fpath, ["texts", key, "text"])
                line = entry.get("line")
                if isinstance(line, dict) and isinstance(line.get("text"), str):
                    self.add(f"text:{key}#line", str(line.get("speaker", "")), sr,
                             ctx + " · реплика персонажа" + ref_s, line["text"],
                             fpath, ["texts", key, "line", "text"])

    # ---- scenes / quests
    def _scene_lines(self, prefix, sid, lines, fpath, base, sr, head, lines_key):
        for i, ln in enumerate(lines):
            if not isinstance(ln, dict):
                continue
            sp = str(ln.get("speaker", ""))
            lp = base + [lines_key, i]
            idb = f"{prefix}:{sid}/lines[{i}]"
            cond = _cond(ln)
            where = f"{head} · реплика {i + 1}{cond}"
            if isinstance(ln.get("context"), str) and not _is_ref(ln["context"]):
                self.add(f"{idb}.context", "ui", sr, where + " · кнопка перед репликой", ln["context"], fpath, lp + ["context"])
            if isinstance(ln.get("prompt"), str) and ln["prompt"] and not _is_ref(ln["prompt"]):
                self.add(f"{idb}.prompt", "narrator", sr, where + " · вопрос выбора", ln["prompt"], fpath, lp + ["prompt"])
            for j, o in enumerate(ln.get("options", []) or []):
                if not isinstance(o, dict):
                    continue
                oid = str(o.get("id", j))
                for fld, desc, spk in (("label", "вариант выбора (кнопка)", "ui"),
                                       ("text", "сказанное после выбора", sp or "agata")):
                    v = o.get(fld)
                    if isinstance(v, str) and v and not _is_ref(v):
                        if fld == "text" and "label" not in o:
                            desc = "вариант выбора (кнопка) и сказанное после выбора"
                        self.add(f"{idb}.options[{oid}].{fld}", spk, sr, f"{where} · вариант «{oid}» · {desc}",
                                 v, fpath, lp + ["options", j, fld])
            if isinstance(ln.get("text"), str) and not _is_ref(ln["text"]):
                self.add(f"{idb}.text", sp, sr, where, ln["text"], fpath, lp + ["text"])
            if isinstance(ln.get("voice_text"), str):
                self.add(f"{idb}.voice_text", sp, sr, where + " · текст для озвучки (не субтитр; теги [..] — подача голоса)",
                         ln["voice_text"], fpath, lp + ["voice_text"])
            for k, sub in enumerate(ln.get("then", []) or []):
                if not isinstance(sub, dict):
                    continue
                ssp = str(sub.get("speaker", "narrator"))
                sw = f"{head} · после реплики {i + 1}, продолжение {k + 1}{_cond(sub)}"
                if isinstance(sub.get("text"), str) and not _is_ref(sub["text"]):
                    self.add(f"{idb}.then[{k}].text", ssp, sr, sw, sub["text"], fpath, lp + ["then", k, "text"])
                if isinstance(sub.get("voice_text"), str):
                    self.add(f"{idb}.then[{k}].voice_text", ssp, sr, sw + " · текст для озвучки",
                             sub["voice_text"], fpath, lp + ["then", k, "voice_text"])

    def _hints(self, prefix, sid, sc, fpath, base, sr, head):
        for k, h in enumerate(sc.get("hints", []) or []):
            if isinstance(h, str) and not _is_ref(h):
                self.add(f"{prefix}:{sid}/hints[{k}]", "ui", sr, f"{head} · подсказка {k + 1} из 3 (кнопка «Подсказка»)",
                         h, fpath, base + ["hints", k])
        if isinstance(sc.get("hint"), str) and not _is_ref(sc["hint"]):
            self.add(f"{prefix}:{sid}/hint", "ui", sr, f"{head} · подсказка", sc["hint"], fpath, base + ["hint"])

    def collect_scenes(self):
        for p in sorted((STORY / "scenes").glob("*.json")):
            if p.name.startswith("_"):
                continue
            rel = f"scenes/{p.name}"
            fpath = f"data/story/{rel}"
            doc = _load(rel)
            ep = p.stem
            for si, sc in enumerate(doc.get("scenes", [])):
                sid = str(sc["id"])
                rooms = ", ".join(sc.get("locations", []))
                sr = f"{ep}/{sid} · {rooms}" if rooms else f"{ep}/{sid}"
                head = f"{sid} «{sc.get('title', '')}»"
                base = ["scenes", si]
                self._scene_lines("scene", sid, sc.get("mandatory_lines", []) or [], fpath, base, sr, head, "mandatory_lines")
                if sc.get("type") == "main" and isinstance(sc.get("goal"), str) and not _is_ref(sc["goal"]):
                    self.add(f"scene:{sid}/goal", "ui", sr, f"{head} · цель в журнале после сцены", sc["goal"], fpath, base + ["goal"])
                gl = sc.get("goal_left") or {}
                for k in ("lead", "head", "none"):
                    if isinstance(gl.get(k), str) and not _is_ref(gl[k]):
                        self.add(f"scene:{sid}/goal_left/{k}", "ui", sr, f"{head} · цель по флагам: {k}", gl[k], fpath, base + ["goal_left", k])
                for j, it in enumerate(gl.get("items", []) or []):
                    if isinstance(it.get("text"), str) and not _is_ref(it["text"]):
                        self.add(f"scene:{sid}/goal_left/items/{j}", "ui", sr, f"{head} · цель по флагам: несделанное", it["text"], fpath, base + ["goal_left", "items", j, "text"])
                self._hints("scene", sid, sc, fpath, base, sr, head)

    def collect_quests(self):
        fpath = "data/story/quests.json"
        doc = _load("quests.json")
        for qi, q in enumerate(doc.get("quests", [])):
            qid = str(q["id"])
            rooms = ", ".join(q.get("locations", []))
            sr = f"quest/{qid} · {rooms}" if rooms else f"quest/{qid}"
            head = f"{qid} «{q.get('title', '')}» (необязательная история)"
            base = ["quests", qi]
            key = "mandatory_lines" if "mandatory_lines" in q else "lines"
            self._scene_lines("quest", qid, q.get(key, []) or [], fpath, base, sr, head, key)
            self._hints("quest", qid, q, fpath, base, sr, head)

    # ---- small catalogues
    def collect_catalogues(self):
        doc = _load("items.json")
        for i, it in enumerate(doc.get("items", [])):
            if isinstance(it.get("name"), str):
                self.add(f"item:{it['id']}/name", "ui", "сумка", "название предмета (сумка, «В сумке: …», рассмотреть)",
                         it["name"], "data/story/items.json", ["items", i, "name"])
        doc = _load("characters.json")
        for i, c in enumerate(doc.get("characters", [])):
            if isinstance(c.get("name"), str):
                self.add(f"char:{c['id']}/name", "ui", "UI", "имя говорящего над репликой",
                         c["name"], "data/story/characters.json", ["characters", i, "name"])
        doc = _load("locations.json")
        for i, l in enumerate(doc.get("locations", [])):
            if isinstance(l.get("name"), str):
                self.add(f"loc:{l['id']}/name", "ui", l["id"], "название места (строка комнаты, слоты сохранений)",
                         l["name"], "data/story/locations.json", ["locations", i, "name"])
        doc = _load("flags.json")
        for fl, d in doc.get("flags", {}).items():
            if isinstance(d, dict) and isinstance(d.get("desc"), str) and d["desc"]:
                self.add(f"flag:{fl}/desc", "ui", "журнал", f"журнал «Что известно» · флаг {fl}",
                         d["desc"], "data/story/flags.json", ["flags", fl, "desc"])

    # ---- hard-coded Russian strings in UI scripts (read-only)
    def collect_ui_code(self):
        str_re = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
        for p in sorted(UI_CODE.glob("*.gd")):
            for no, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
                code = _strip_gd_comment(line)
                for m in str_re.finditer(code):
                    s = m.group(1)
                    if CYR.search(s):
                        h = hashlib.sha1(s.encode("utf-8")).hexdigest()[:10]
                        rel = p.relative_to(ROOT).as_posix()
                        self.add(f"ui_code:{p.name}:{h}", "ui", "UI", f"зашито в коде {rel}:{no} (импорт не пишет — правит программист)",
                                 s, rel, [], importable=False)

    def run(self) -> list[Row]:
        self.locations = {l["id"]: l for l in _load("locations.json").get("locations", [])}
        self.items = {it["id"]: it for it in _load("items.json").get("items", [])}
        self.voice = _load("voice.json") if (STORY / "voice.json").exists() else {}
        self._scan_refs()
        self.collect_texts()
        self.collect_scenes()
        self.collect_quests()
        self.collect_catalogues()
        self.collect_ui_code()
        # Normalise file paths and make sure ids are unique.
        seen = {}
        for r in self.rows:
            if r.id in seen:
                # ui_code with equal strings in one file: disambiguate deterministically
                if r.id.startswith("ui_code:"):
                    n = 2
                    while f"{r.id}~{n}" in seen:
                        n += 1
                    r.id = f"{r.id}~{n}"
                else:
                    raise SystemExit(f"export_texts: duplicate id {r.id} ({seen[r.id].file} and {r.file})")
            seen[r.id] = r
        return self.rows


def _strip_gd_comment(line: str) -> str:
    out = []
    q = None
    i = 0
    while i < len(line):
        c = line[i]
        if q:
            out.append(c)
            if c == "\\" and i + 1 < len(line):
                out.append(line[i + 1])
                i += 2
                continue
            if c == q:
                q = None
        else:
            if c == "#":
                break
            if c in "\"'":
                q = c
            out.append(c)
        i += 1
    return "".join(out)


def collect() -> list[Row]:
    return Collector().run()


def category(row_id: str) -> str:
    if row_id.startswith("text:"):
        key = row_id[5:]
        sec = key.split(".")[0]
        kind = "line" if key.endswith("#line") else "text"
        if sec in ("ui", "map", "ach", "item", "examine", "mech"):
            return f"text:{sec}" + ("#line" if kind == "line" else "")
        return "text:room" + ("#line" if kind == "line" else "")
    if row_id.startswith(("scene:", "quest:")):
        pre = row_id.split(":")[0]
        tail = row_id.split("/", 1)[1]
        if tail.startswith("lines"):
            fld = re.sub(r"\[[^\]]*\]", "", tail.split(".", 1)[1]) if "." in tail else tail
            return f"{pre}:lines.{fld}"
        return f"{pre}:" + re.sub(r"\[.*", "", tail)
    return row_id.split(":")[0]


def write_tsv(rows: list[Row], out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="") as f:
        f.write("\t".join(COLUMNS) + "\n")
        for r in rows:
            f.write("\t".join(esc(str(x)) for x in (r.id, r.speaker, r.scene_room, r.context, r.text)) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description="Export all player-visible texts of data/story to TSV.")
    ap.add_argument("--out", default=str(DEFAULT_OUT), help="output TSV (default Docs/text_export/ru_all.tsv)")
    ap.add_argument("--stats", action="store_true", help="print row counts per category")
    a = ap.parse_args()
    rows = collect()
    out = Path(a.out)
    write_tsv(rows, out)
    print(f"[export_texts] {len(rows)} rows → {out}")
    if a.stats:
        from collections import Counter
        c = Counter(category(r.id) for r in rows)
        for k, v in sorted(c.items()):
            print(f"  {v:5d}  {k}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
